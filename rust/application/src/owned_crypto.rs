//! Current-user DPAPI envelope, bound to purpose, version and canonical store location.
use crate::{err, AppError};
use windows_sys::Win32::{Foundation::LocalFree, Security::Cryptography::*};
pub(super) fn transform(bytes: &[u8], binding: &[u8], seal: bool) -> Result<Vec<u8>, AppError> {
    let input = CRYPT_INTEGER_BLOB {
        cbData: bytes
            .len()
            .try_into()
            .map_err(|_| err("owned_store_invalid"))?,
        pbData: bytes.as_ptr().cast_mut(),
    };
    let entropy = CRYPT_INTEGER_BLOB {
        cbData: binding
            .len()
            .try_into()
            .map_err(|_| err("owned_store_invalid"))?,
        pbData: binding.as_ptr().cast_mut(),
    };
    let mut output = CRYPT_INTEGER_BLOB::default();
    // SAFETY: input buffers live through the synchronous call; Windows allocates output.
    let ok = unsafe {
        if seal {
            CryptProtectData(
                &input,
                std::ptr::null(),
                &entropy,
                std::ptr::null(),
                std::ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
        } else {
            CryptUnprotectData(
                &input,
                std::ptr::null_mut(),
                &entropy,
                std::ptr::null(),
                std::ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
        }
    };
    if ok == 0 {
        return Err(err("owned_store_invalid"));
    }
    // SAFETY: successful DPAPI returns cbData initialized bytes allocated by LocalAlloc.
    let result =
        unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec() };
    unsafe {
        LocalFree(output.pbData.cast());
    }
    Ok(result)
}
