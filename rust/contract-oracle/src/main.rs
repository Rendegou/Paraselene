//! Synthetic cross-language oracle. No database, credential or network capability.
use serde::{Deserialize, Serialize};
use std::{env, error::Error, fs};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Fixture {
    schema_version: u32,
    vectors: Vec<Vector>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Vector {
    id: String,
    body: String,
    from_utf16: usize,
    to_utf16: usize,
    start_scalar: usize,
    end_scalar: usize,
    quote: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Verified {
    id: String,
    body_hash: String,
    quote_hash: String,
    utf16_length: usize,
    scalar_length: usize,
}

fn verify(vector: &Vector) -> Result<Verified, Box<dyn Error>> {
    let units: Vec<u16> = vector.body.encode_utf16().collect();
    let prefix = units
        .get(..vector.from_utf16)
        .ok_or("prefix out of range")?;
    let slice = units
        .get(vector.from_utf16..vector.to_utf16)
        .ok_or("range invalid")?;
    let prefix = String::from_utf16(prefix)?;
    let quote = String::from_utf16(slice)?;
    let scalars: String = vector
        .body
        .chars()
        .skip(vector.start_scalar)
        .take(
            vector
                .end_scalar
                .checked_sub(vector.start_scalar)
                .ok_or("reversed scalar range")?,
        )
        .collect();
    if prefix.chars().count() != vector.start_scalar
        || prefix.chars().count() + quote.chars().count() != vector.end_scalar
        || quote != vector.quote
        || scalars != quote
        || quote.is_empty()
    {
        return Err(format!("fixture mismatch: {}", vector.id).into());
    }
    Ok(Verified {
        id: vector.id.clone(),
        // Same canonical formula as novel-core::quote_hash: exact UTF-8, BLAKE3 hex.
        body_hash: blake3::hash(vector.body.as_bytes()).to_hex().to_string(),
        quote_hash: blake3::hash(quote.as_bytes()).to_hex().to_string(),
        utf16_length: units.len(),
        scalar_length: vector.body.chars().count(),
    })
}

fn main() -> Result<(), Box<dyn Error>> {
    let path = env::args()
        .nth(1)
        .ok_or("usage: contract-oracle <synthetic-fixture.json>")?;
    let fixture: Fixture = serde_json::from_str(&fs::read_to_string(path)?)?;
    if fixture.schema_version != 1 {
        return Err("unsupported fixture schema".into());
    }
    if fixture.vectors.is_empty() {
        return Err("empty fixture".into());
    }
    let verified = fixture
        .vectors
        .iter()
        .map(verify)
        .collect::<Result<Vec<_>, _>>()?;
    println!("{}", serde_json::to_string_pretty(&verified)?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unicode_coordinates_are_checked_and_line_endings_change_hash() {
        let mut vector = Vector {
            id: "synthetic".into(),
            body: "甲🌙\r\n乙".into(),
            from_utf16: 1,
            to_utf16: 3,
            start_scalar: 1,
            end_scalar: 2,
            quote: "🌙".into(),
        };
        let original = verify(&vector).unwrap();
        vector.body = "甲🌙\n乙".into();
        assert_ne!(original.body_hash, verify(&vector).unwrap().body_hash);
        vector.to_utf16 = 2;
        assert!(verify(&vector).is_err());
    }

    #[test]
    fn empty_stale_or_wrong_scalar_range_is_rejected() {
        let mut vector = Vector {
            id: "synthetic".into(),
            body: "abc".into(),
            from_utf16: 0,
            to_utf16: 1,
            start_scalar: 0,
            end_scalar: 1,
            quote: "x".into(),
        };
        assert!(verify(&vector).is_err());
        vector.quote = "a".into();
        vector.end_scalar = 2;
        assert!(verify(&vector).is_err());
        vector.to_utf16 = 0;
        vector.end_scalar = 0;
        vector.quote.clear();
        assert!(verify(&vector).is_err());
    }
}
