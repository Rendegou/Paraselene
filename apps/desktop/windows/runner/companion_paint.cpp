// 伴侣窗口的分层绘制实现：把当前帧合成到 32 位内存位图，再整体 UpdateLayeredWindow。
//
// 线程模型：只在伴侣窗口的消息循环（UI 线程）中调用，GDI/GDI+ 对象不跨线程。
// 资源：DC、位图与 GDI+ 对象都在本函数内创建并释放，失败路径同样回收。
// 失败策略：帧号或图像无效、合成或更新失败都返回 false，由调用方触发 Fault。

#include "companion_window.h"

// 以窗口 DPI 计算 150 逻辑像素的方形画布，合成透明图层后原子更新窗口。
// 返回 false 表示绘制或更新失败，调用方必须停用伴侣窗口而不是继续使用半成品。
bool CompanionWindow::Paint(size_t frame) {
  if (!pet_ || frame >= images_.size() || !images_[frame]) return false;
  const UINT dpi = GetDpiForWindow(pet_);
  const int pixels = MulDiv(150, dpi ? dpi : 96, 96);
  const HDC screen = GetDC(nullptr);
  if (!screen) return false;
  const HDC memory = CreateCompatibleDC(screen);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = pixels; info.bmiHeader.biHeight = -pixels;
  info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  const HBITMAP bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!memory || !bitmap) {
    if (bitmap) DeleteObject(bitmap);
    if (memory) DeleteDC(memory);
    ReleaseDC(nullptr, screen); return false;
  }
  const auto previous = SelectObject(memory, bitmap);
  bool painted = false;
  {
    Gdiplus::Bitmap target(pixels, pixels, pixels * 4, PixelFormat32bppPARGB, static_cast<BYTE*>(bits));
    Gdiplus::Graphics graphics(&target);
    graphics.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
    graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
    graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    painted = graphics.DrawImage(images_[frame].get(), 0, 0, pixels, pixels) == Gdiplus::Ok;
  }
  RECT rect{}; GetWindowRect(pet_, &rect);
  POINT destination{rect.left, rect.top}, origin{};
  SIZE size{pixels, pixels};
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  const bool updated = painted && UpdateLayeredWindow(pet_, screen, &destination, &size, memory, &origin, 0, &blend, ULW_ALPHA);
  SelectObject(memory, previous); DeleteObject(bitmap); DeleteDC(memory); ReleaseDC(nullptr, screen);
  return updated;
}
