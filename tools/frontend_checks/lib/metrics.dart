// 自有前端 AST 度量；不解析凭据、数据库或第三方源码。
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/source/line_info.dart';

/// 一项可定位、可机器读取的规则违反。
class Finding {
  Finding(
    this.rule,
    this.path,
    this.line,
    this.symbol,
    this.actual,
    this.limit,
  );
  final String rule;
  final String path;
  final int line;
  final String symbol;
  final num actual;
  final int limit;
  Map<String, Object> toJson() => {
    'rule': rule,
    'path': path,
    'line': line,
    'symbol': symbol,
    'actual': actual,
    'limit': limit,
  };
}

/// 通过词法 token 覆盖行统计有效行，多行字符串也占用真实源代码行。
int effectiveLines(Token first, Token last, LineInfo lines) {
  final occupied = <int>{};
  for (Token? token = first; token != null; token = token.next) {
    if (!token.isSynthetic && token.length > 0 && token.type != TokenType.EOF) {
      final start = lines.getLocation(token.offset).lineNumber;
      final end = lines.getLocation(token.end - 1).lineNumber;
      for (var line = start; line <= end; line++) {
        occupied.add(line);
      }
    }
    if (identical(token, last) || token.type == TokenType.EOF) break;
  }
  return occupied.length;
}

/// 对完整文件和每个独立 FunctionBody 检查，不豁免既有违规。
List<Finding> inspectSource(String path, String source, {bool theme = false}) {
  final parsed = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  );
  final findings = <Finding>[];
  for (final error in parsed.errors) {
    findings.add(
      Finding(
        'syntax',
        path,
        parsed.lineInfo.getLocation(error.offset).lineNumber,
        error.message,
        1,
        0,
      ),
    );
  }
  final count = effectiveLines(
    parsed.unit.beginToken,
    parsed.unit.endToken,
    parsed.lineInfo,
  );
  if (count > 400)
    findings.add(Finding('file-lines', path, 1, '<module>', count, 400));
  parsed.unit.accept(_FunctionCheck(path, parsed.lineInfo, findings, theme));
  return findings;
}

class _FunctionCheck extends RecursiveAstVisitor<void> {
  _FunctionCheck(this.path, this.lines, this.findings, this.theme);
  final String path;
  final LineInfo lines;
  final List<Finding> findings;
  final bool theme;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _body(node.body, _functionName(node));
    super.visitFunctionExpression(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _body(node.body, node.name.lexeme);
    if (_returnsWidget(node.returnType) && !_isOverrideBuild(node)) {
      _record('widget-builder', node, node.name.lexeme);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_returnsWidget(node.returnType)) {
      _record('widget-builder', node, node.name.lexeme);
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _body(node.body, node.name?.lexeme ?? '<constructor>');
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type
        .toSource()
        .split('<')
        .first
        .split('.')
        .last;
    if (type == 'PopupMenuButton') {
      _popupMenu(node, node.argumentList);
    }
    if (!theme && {'Color', 'MaterialColor', 'TextStyle'}.contains(type)) {
      _record('theme-constructor', node, type);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (!theme && node.prefix.name == 'Colors') {
      _record('theme-color', node, node.toSource());
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (!theme &&
        target is PrefixedIdentifier &&
        target.identifier.name == 'Colors') {
      _record('theme-color', node, node.toSource());
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    final name = node.name.label.name;
    final invocation = node.parent?.parent;
    final isUiSize =
        name == 'size' &&
        invocation is MethodInvocation &&
        invocation.methodName.name == 'ui' &&
        invocation.target?.toSource().split('.').last == 'WorkbenchTokens';
    if (name == 'fontSize' || isUiSize) {
      final size = _numeric(node.expression);
      if (size != null && size < 12) {
        findings.add(
          Finding(
            'minimum-font-size',
            path,
            lines.getLocation(node.offset).lineNumber,
            name,
            size,
            12,
          ),
        );
      }
    }
    if (!theme &&
        name.startsWith('fontFamily') &&
        (node.expression is StringLiteral || node.expression is ListLiteral)) {
      _record('theme-font', node, name);
    }
    if (name == 'onError' && _emptyHandler(node.expression)) {
      _record('empty-error-handler', node, name);
    }
    super.visitNamedExpression(node);
  }

  num? _numeric(Expression expression) => switch (expression) {
    IntegerLiteral(:final value) => value,
    DoubleLiteral(:final value) => value,
    ParenthesizedExpression(:final expression) => _numeric(expression),
    PrefixExpression(:final operator, :final operand)
        when operator.lexeme == '-' =>
      switch (_numeric(operand)) {
        final num value => -value,
        _ => null,
      },
    _ => null,
  };

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (name == 'PopupMenuButton') _popupMenu(node, node.argumentList);
    final target = node.target?.toSource().split('.').last;
    if (!theme &&
        ({'Color', 'MaterialColor', 'TextStyle'}.contains(name) ||
            ({'Color', 'MaterialColor'}.contains(target) &&
                {'fromARGB', 'fromRGBO', 'from'}.contains(name)))) {
      _record('theme-constructor', node, node.toSource());
    }
    if (name == 'catchError' &&
        node.argumentList.arguments.isNotEmpty &&
        _emptyHandler(node.argumentList.arguments.first)) {
      _record('empty-error-handler', node, name);
    }
    if (name == 'ignore' &&
        node.target != null &&
        node.argumentList.arguments.isEmpty) {
      _record('ignored-future', node, name);
    }
    super.visitMethodInvocation(node);
  }

  void _popupMenu(AstNode node, ArgumentList arguments) {
    final hasCustomChild = arguments.arguments.any(
      (argument) =>
          argument is NamedExpression &&
          argument.name.label.name == 'child' &&
          argument.expression is! NullLiteral,
    );
    if (hasCustomChild)
      _record('menu-state-style', node, 'PopupMenuButton.child');
  }

  bool _emptyHandler(Expression expression) {
    if (expression is! FunctionExpression) return false;
    final body = expression.body;
    if (body is ExpressionFunctionBody) return body.expression is NullLiteral;
    if (body is! BlockFunctionBody) return false;
    final statements = body.block.statements;
    return statements.isEmpty ||
        (statements.length == 1 &&
            statements.first is ReturnStatement &&
            ((statements.first as ReturnStatement).expression == null ||
                (statements.first as ReturnStatement).expression
                    is NullLiteral));
  }

  void _body(FunctionBody body, String symbol) {
    if (body is EmptyFunctionBody) return;
    final count = effectiveLines(body.beginToken, body.endToken, lines);
    if (count > 60) {
      findings.add(
        Finding(
          'function-lines',
          path,
          lines.getLocation(body.offset).lineNumber,
          symbol,
          count,
          60,
        ),
      );
    }
  }

  void _record(String rule, AstNode node, String symbol) {
    findings.add(
      Finding(
        rule,
        path,
        lines.getLocation(node.offset).lineNumber,
        symbol,
        1,
        0,
      ),
    );
  }

  String _functionName(FunctionExpression node) {
    final parent = node.parent;
    return parent is FunctionDeclaration ? parent.name.lexeme : '<callback>';
  }

  bool _returnsWidget(TypeAnnotation? type) =>
      {'Widget', 'Widget?'}.contains(type?.toSource().split('.').last);

  bool _isOverrideBuild(MethodDeclaration node) =>
      node.name.lexeme == 'build' &&
      node.metadata.any(
        (annotation) => annotation.name.toSource() == 'override',
      );
}
