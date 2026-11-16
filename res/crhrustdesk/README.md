# รันและ build CrhRustDesk ในเครื่อง dev

การเลือกบทบาทเครื่องและกำหนดสิทธิ์ username อยู่ใน source แล้ว แต่ยังไม่ build หรือเปิด AD จริง ดู [ติดตั้งเครื่องปลายทาง/เครื่อง IT](ENDPOINT-INSTALL-TH.md) และ [AD/Management](AD-SETUP-TH.md) หน้า Management ใช้ `http://127.0.0.1:21120/_admin/` หลัง deploy บริการรุ่นใหม่ ผู้ดูแลเลือก username รายคนได้โดยไม่บังคับกลุ่ม IT

สำหรับติดตั้งแบบดับเบิลคลิก ดู [INSTALL-EASY-TH.md](INSTALL-EASY-TH.md) สร้างไฟล์ติดตั้งจาก release bundle ที่ build แล้วด้วย Inno Setup 6.6.1:

```powershell
$bundle = Get-ChildItem .\target -Directory -Filter 'CrhRustDesk-20*' | Sort-Object Name -Descending | Select-Object -First 1
.\res\crhrustdesk\Build-EasySetup.ps1 -BundlePath $bundle.FullName
```

ผลลัพธ์อยู่ที่ `target/CrhRustDesk-EasySetup/CrhRustDesk-Setup.exe` ไม่ต้อง build Rust หรือ Flutter ซ้ำ ตัวติดตั้งใช้ติดตั้งหรืออัปเดตและขอสิทธิ์ Administrator เอง

## เปิดสิทธิ์บัญชีสำหรับรีโมตโดยแจ้งเตือนปลายทาง

เตรียม Python venv บน server แล้วเริ่มบริการออกใบอนุญาต session ก่อน build client รุ่นนี้:

```powershell
python -m venv D:\Project\2569\CrhRustDesk-build-tools\permit-python
& D:\Project\2569\CrhRustDesk-build-tools\permit-python\Scripts\python.exe -m pip install --only-binary=:all: -r .\res\crhrustdesk\account-server\requirements.txt
.\res\crhrustdesk\Start-DevPermitServer.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools
```

บริการฟังเฉพาะ `127.0.0.1:21120` และใช้ `/crhrustdesk/*` ผ่าน Caddy HTTPS เดิม หาก Caddy รุ่นก่อนยังทำงาน ให้หยุดเฉพาะโปรเซส Caddy ของชุด dev แล้วเริ่มด้วย `Start-DevTls.ps1` รุ่นนี้ ไม่เปิดพอร์ต 21120 ให้ LAN

บัญชีที่ server ยืนยัน `is_admin=true` ได้สิทธิ์ทุกเครื่องตาม `allow_admin` ใน `dev-server/unattended-users.json` ผู้ใช้อื่นได้รับสิทธิ์ที่ผู้ดูแลกำหนดราย username/รายเครื่องใน Management การเปลี่ยน policy ใช้กับใบอนุญาตใหม่ทันที ใบเดิมมีอายุไม่เกิน 60 วินาทีและผูกกับ connection นั้น การถอนสิทธิ์ไม่ตัด session ที่เปิดอยู่ ให้หยุดจาก connection manager ที่ปลายทาง ใช้ Set-UnattendedUser.ps1 ได้เฉพาะตอนบริการหยุด เพื่อไม่ให้เขียน policy พร้อมกับ Management

`permit.key` เป็น private signing key เก็บบน server เท่านั้น `permit-public-key.txt` เป็น public key ที่ Build.ps1 ฝังใน client ต้อง build ใหม่เมื่อเปลี่ยน signing key ใช้นาฬิกา server และ client ที่ตรงกัน รายละเอียด protocol อยู่ใน [CRHRUSTDESK-ACCESS-DESIGN.md](../../docs/CRHRUSTDESK-ACCESS-DESIGN.md)

ชุดนี้ใช้ RustDesk client แบบเปิดซอร์ส ร่วมกับ `lejianwen/rustdesk-api` รุ่น `v2.7` และ `lejianwen/rustdesk-server` รุ่น `v0.1.2` ไม่มีค่า license ของ RustDesk Server Pro ตัว API ใช้ MIT ส่วน client และ server ต้องคงเงื่อนไข AGPL และประกาศของต้นทางเมื่อแจกจ่าย

## เปิดเซิร์ฟเวอร์ทดลองบน Windows

จาก root ของ repo รันคำสั่งต่อไปนี้ โดยเปลี่ยน ToolsRoot หากติดตั้งเครื่องมือไว้ที่อื่น

```powershell
.\res\crhrustdesk\Start-DevServer.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools
```

สคริปต์ตรวจ SHA256 ของ archive เทียบกับ release ที่ตรึงไว้ก่อนแตกไฟล์ในครั้งแรก แล้วเปิด API ที่ `127.0.0.1:21114` พร้อม `hbbs` และ `hbbr` โดยเปิด `--must-login Y` และใช้ JWT secret เดียวกันกับ API

เข้า [แผงจัดการบนเครื่อง dev](http://127.0.0.1:21114/_admin/) ด้วยบัญชี `admin` รหัสถูกสุ่มและเก็บใน `dev-server/admin.credential.xml` ด้วย Windows DPAPI อ่านได้ด้วยบัญชี Windows ที่สร้างไฟล์บนเครื่องนี้เท่านั้น ห้ามนำไฟล์ credential, database หรือ private key ไปใส่ในชุดติดตั้ง client

หากต้องอ่านรหัสผ่าน ให้รันใน PowerShell บนเครื่อง dev เอง

```powershell
$account = Import-Clixml D:\Project\2569\CrhRustDesk-build-tools\dev-server\admin.credential.xml
$account.GetNetworkCredential().Password
```

สร้างบัญชีผู้ใช้ทั่วไปสำหรับทดลอง

```powershell
.\res\crhrustdesk\New-DevUser.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools -Username AD_USERNAME
```

รหัสของผู้ใช้ทั่วไปเก็บเป็น DPAPI credential แยกจากบัญชี admin สคริปต์ตรวจว่าบัญชีใหม่ login ได้และไม่มีสิทธิ์ admin ไฟล์ credential เก็บรหัสเริ่มต้น หากเปลี่ยนรหัสผ่านในหน้าเว็บแล้ว ให้ใช้รหัสใหม่ การรันสคริปต์ซ้ำไม่รีเซ็ตรหัสของบัญชีเดิม

หยุดเฉพาะโปรเซสเซิร์ฟเวอร์ของชุดนี้โดยเก็บข้อมูลไว้

```powershell
.\res\crhrustdesk\Stop-DevServer.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools
```

API ใช้ HTTP เฉพาะ loopback ห้ามเปิด HTTP นี้ให้เครื่องปลายทางส่งรหัสผ่านผ่าน LAN สำหรับ LAN ให้ระบุ `-ServerAddress` ตอนเริ่ม server และใช้ `Start-DevTls.ps1` ซึ่งใช้ Caddy แบบเปิดซอร์สเป็น HTTPS reverse proxy ดูขั้นตอน certificate และ Firewall ใน LAN-SETUP-TH.md

`hbbs` และ `hbbr` ฟังทุก interface ตามพฤติกรรมของ binary ต้นทาง สคริปต์ไม่ได้เพิ่ม Firewall rules พอร์ต `21118–21119` เป็น WebSocket ของ server ให้ปิดจาก LAN เมื่อใช้ native client เท่านั้น

## สร้าง bridge และ build client

เครื่องมือแยกอยู่ใน ToolsRoot โดยสคริปต์ใช้ Flutter `3.24.5`, Rust `1.75.0`, codegen `1.80.1`, cargo-expand `1.0.95`, LLVM `15.0.6`, CMake `4.3.0`, NASM `2.16.03` และ Visual C++ x64 พร้อม Windows SDK ใช้ vcpkg commit `9e593bb18ea69cc5095e012465dcd675a822ed0d` กับ dependencies และ overlay ของ repo

สร้าง dependencies ก่อน

```powershell
. .\res\crhrustdesk\Initialize-BuildEnvironment.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools
& "$env:VCPKG_ROOT\vcpkg.exe" install --triplet x64-windows-static "--x-install-root=$env:VCPKG_ROOT\installed"
```

ใช้ Flutter SDK patch และ custom Windows engine ตาม Windows x64 CI ด้วย ไฟล์ patch อยู่ที่ `.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff` และ engine มาจาก [rustdesk/engine](https://github.com/rustdesk/engine/releases/tag/main)

โดยปกติ AGENTS.md กำหนดให้ใช้ bridge จาก CI สำหรับงานนี้ผู้ใช้อนุญาตให้รัน codegen ในเครื่องอย่างชัดเจน จึงใช้คำสั่งต่อไปนี้ได้

```powershell
.\res\crhrustdesk\Generate-Bridge.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools
.\res\crhrustdesk\Build.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools -CheckOnly
.\res\crhrustdesk\Build.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools
```

ชุดไฟล์ที่ build สำเร็จจะอยู่ใน `target/CrhRustDesk-<timestamp>/` และมี `CrhRustDesk.exe`, DLL, assets, license และ `Install.ps1` เก็บทั้งโฟลเดอร์ไว้ด้วยกัน

บนเครื่องปลายทาง เปิด PowerShell แบบ Administrator แล้วรัน `Install.ps1` จากโฟลเดอร์ชุดติดตั้ง ส่งค่า `-IdServer`, `-RelayServer`, `-ApiServer` และ `-PublicKey` ของระบบจริง โดย API บน LAN ต้องเป็น HTTPS สคริปต์จะตั้ง Direct IP เป็นปิดและใช้การกดยอมรับ session ที่ปลายทาง จากนั้น login บัญชีส่วนกลางในแอป

ชื่อ CrhRustDesk เปิดผ่าน Cargo feature `crhrustdesk` โดย `Build.ps1` ตั้ง `CRHRUSTDESK_BUILD=1` ให้ระหว่าง build รุ่น dev ตั้ง default server เป็น loopback และใส่ public key ของ dev server ตั้งแต่เริ่มโปรแกรม จึงไม่ใช้ public server เป็นค่าเริ่มต้น ส่ง `-IdServer`, `-RelayServer`, `-ApiServer` และ `-PublicKey` ให้ Build.ps1 เมื่อต้องการฝังค่า server ของ LAN โดยไม่มี username/password อยู่ใน binary

ไม่ได้เปลี่ยนชื่อ crate หรือแก้ submodule รุ่นที่ไม่เปิด feature นี้ยังใช้เส้นทางเดิมของ RustDesk

## ขอบเขตการตรวจ

ตรวจบน dev API จริงแล้วว่าบัญชีทั่วไป login ได้, รหัสผ่านผิดถูกปฏิเสธ, ผู้ที่ยังไม่ login ดูรายการผู้ใช้ไม่ได้ และบัญชีทั่วไปดูรายการผู้ใช้ทั้งหมดไม่ได้ ตรวจ TCP signalling ของ `hbbs` จริงแล้วว่าไม่มี token หรือส่ง token ปลอมถูกปฏิเสธ และ token ที่ได้จากการ login จริงผ่าน authentication จนถึงขั้นตอบว่าไม่พบ ID ทดสอบ

ผลเหล่านี้ยังไม่ยืนยัน session รีโมตที่ `172.29.0.52`, การเข้ารหัสภาพและ input, certificate ของ client, EDR หรือการลงลายเซ็นตัวติดตั้ง

สร้าง bridge และ release bundle ในเครื่องสำเร็จแล้ว โปรแกรมเปิดด้วยชื่อหน้าต่าง CrhRustDesk และตอบสนองปกติ ตรวจว่าตัวตน public key ของ client อยู่ในฐานข้อมูล dev server แล้ว และทดสอบ login ผ่าน HTTPS โดยตรวจ certificate chain กับ IP hostname จาก CA ของ dev ก่อนส่ง token ไปยัง hbbs ได้สำเร็จ การตรวจ HTTPS นี้ใช้ CA ระบุเฉพาะการทดสอบ ไม่ได้เพิ่ม CA เข้า trust store ของ Windows

การบังคับ login ของ server fork ตรวจ JWT ไม่ใช่หลักฐานว่ามี ACL รายเครื่องครบถ้วน และ token ที่ออกไปแล้วอาจใช้ได้จนหมดอายุแม้ปิดบัญชีไปแล้ว ชุด dev ตั้งอายุ token เป็น 1 ชั่วโมง ยังต้องใช้การยอมรับหรือรหัสผ่านของปลายทางเพื่ออนุญาต session

ไฟล์เดิมที่เปลี่ยนมีเฉพาะ `Cargo.toml` สำหรับ feature, `src/lib.rs` สำหรับลงทะเบียน module, `src/common.rs` สำหรับเรียกตั้งชื่อและค่าเริ่มต้นตอนเริ่มโปรแกรม, `build.py` สำหรับเปิด feature และ Windows CMake กับ `Runner.rc` สำหรับชื่อใน metadata ของไฟล์ ค่าเริ่มต้นเฉพาะรุ่นอยู่ใน `src/crhrustdesk.rs` ส่วนระบบบัญชีใช้โปรเซส server แยก ไม่มีการแก้ protocol หรือระบบตรวจรหัสผ่านเดิมของ client
