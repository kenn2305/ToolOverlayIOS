# Cai dat moi truong mot nut

Bo cai nay danh cho Windows 10 2004 tro len hoac Windows 11.

Goi build tao ra danh cho jailbreak rootless tren iOS 15-16. Tweak chua ca
`arm64` va `arm64e`, trong do `arm64e` duoc kiem tra bat buoc cho iPhone XS,
XS Max va cac dong A12 tro len.

## Cach dung

1. Giai nen toan bo thu muc project.
2. Bam dup `SETUP_ENVIRONMENT.cmd`.
3. Chap nhan quyen Administrator.
4. Neu Windows yeu cau restart, setup se tu chay lai sau khi dang nhap.
5. Doi den khi setup build thu thanh cong.

Neu co loi, gui file moi nhat trong thu muc `setup-logs` de kiem tra.

Setup se tu dong cai:

- WSL2 va Ubuntu
- Linux build packages
- Tai khoan Linux `builder`
- Theos
- iOS LLVM/Clang toolchain
- Patched iPhoneOS SDK do Theos installer cung cap
- `ldid`, `dpkg`, `fakeroot`, `xz`
- `allemande` cho arm64e
- SDK iPhoneOS 14.5 voi deployment target iOS 15.0
- Visual Studio Code neu `winget` co san

Sau khi cai xong:

- Bam `BUILD_PROJECT.cmd` de build lai project.
- File `.deb` nam trong thu muc `packages`.

May can ket noi Internet trong lan cai dau. Khong di chuyen rieng cac file
`SETUP_ENVIRONMENT.cmd` va `BUILD_PROJECT.cmd` ra khoi thu muc project.
