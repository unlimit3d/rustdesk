# รัน RustDesk ภายในเครือข่าย LAN

คู่มือนี้ใช้ Windows เป็นเครื่องควบคุมและเครื่องปลายทาง โดยถือว่า local หมายถึงเครื่องสองเครื่องใน LAN เดียวกัน ตัวอย่าง IP ต้องเปลี่ยนให้ตรงกับระบบของคุณ

## เลือกวิธีเชื่อมต่อ

| วิธี | ต้องมีเซิร์ฟเวอร์ภายใน | การเข้ารหัส |
| --- | --- | --- |
| Direct IP | ไม่ต้อง | เส้นทาง Direct IP ใน repo นี้ไม่เปิดการเข้ารหัสของ RustDesk |
| เชื่อมต่อด้วย ID ผ่านเซิร์ฟเวอร์ภายใน | ต้องมี `hbbs` และ `hbbr` | ตั้ง public key ให้ถูกต้อง และตรวจสถานะ encrypted ในแต่ละ session |

ถ้าเกณฑ์ security บังคับให้เข้ารหัสข้อมูลระหว่างทาง Direct IP เพียงอย่างเดียวไม่ผ่านเกณฑ์นั้น ใช้วิธีเซิร์ฟเวอร์ภายในด้านล่าง หรือใช้ Direct IP ผ่าน VPN ที่องค์กรอนุมัติ การอยู่ใน LAN และการตั้งรหัสผ่านไม่ได้ทำให้ข้อมูล session เข้ารหัส

นี่เป็นการตรวจเส้นทางโค้ดและเอกสาร ไม่ใช่ผล pentest หรือใบรับรอง หาก security หมายถึง Defender, SmartScreen หรือ EDR ต้องทดสอบไฟล์ที่จะส่งมอบกับระบบนั้นจริงด้วย

## ทดลอง Direct IP บน Windows

ตัวอย่างเครื่องปลายทางคือ `192.168.1.20` และเครื่องควบคุมคือ `192.168.1.10`

1. ติดตั้ง RustDesk จาก [releases ทางการ](https://github.com/rustdesk/rustdesk/releases) บนทั้งสองเครื่อง หรือใช้ไฟล์ที่ทีม build และตรวจสอบแล้ว
2. เปิด RustDesk บนเครื่องปลายทาง หากต้องควบคุม UAC หรือหน้าจอเข้าสู่ระบบ ให้ติดตั้ง service ผ่านตัวติดตั้งของโปรแกรม
3. ไปที่ **Settings > Security** และปลดล็อกการตั้งค่า
4. เปิด **Enable direct IP access** และใช้พอร์ต `21118` ตรวจว่า service ไม่ได้อยู่ในสถานะหยุด
5. ตั้งการยืนยันตัวตน เช่น ให้ผู้ใช้ปลายทางกดยอมรับ หรือใช้รหัสผ่านเฉพาะเครื่องที่เดายาก สำหรับ unattended access ให้ตั้ง permanent password
6. ปิด file transfer, clipboard, terminal และ TCP tunneling ที่ไม่จำเป็นในสิทธิ์การเข้าถึง
7. ดู IPv4 ของเครื่องปลายทางด้วย `ipconfig` เลือก IP ของ LAN ที่เครื่องควบคุมเข้าถึงได้

ถ้า Windows Firewall บล็อกพอร์ต ให้เปิด PowerShell แบบ Administrator บนเครื่องปลายทาง แล้วเพิ่มกฎเฉพาะ IP เครื่องควบคุม คำสั่งนี้เหมาะกับเครือข่ายที่เชื่อถือได้และตั้ง profile เป็น Private

```powershell
New-NetFirewallRule -Name 'RustDesk-LAN-Direct' -DisplayName 'RustDesk LAN Direct' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 21118 -RemoteAddress 192.168.1.10 -Profile Private
```

ตรวจ existing allow rules ของ RustDesk ด้วย กฎใหม่นี้ไม่ทำให้กฎเดิมที่เปิดกว้างอยู่แคบลง ห้ามปิด Firewall ทั้งระบบเพื่อแก้ปัญหาเชื่อมต่อ

บนเครื่องควบคุม ทดสอบพอร์ตด้วย PowerShell

```powershell
Test-NetConnection 192.168.1.20 -Port 21118
```

เมื่อ `TcpTestSucceeded` เป็น `True` ให้เปิด RustDesk กรอก `192.168.1.20:21118` ในช่องเครื่องปลายทาง แล้วกดเชื่อมต่อ ผ่านการยืนยันตัวตนก่อนเริ่มควบคุม ผลตรวจพอร์ตยืนยันเพียงว่า TCP ไปถึง ไม่ได้ยืนยันว่าการ login หรือการเข้ารหัสผ่านแล้ว

ถ้าเชื่อมต่อไม่ได้ ให้ตรวจว่าโปรแกรมฟังพอร์ตบนเครื่องปลายทาง

```powershell
Get-NetTCPConnection -LocalPort 21118 -State Listen
```

หากไม่มี listener ให้ตรวจ Direct IP, service และพอร์ต หากมี listener แต่ทดสอบจากอีกเครื่องไม่ผ่าน ให้ตรวจ Firewall, VLAN และ Wi-Fi client isolation

เมื่อเลิกทดลอง ให้ปิด Direct IP ในโปรแกรม และลบกฎที่สร้างไว้ด้วย PowerShell แบบ Administrator

```powershell
Remove-NetFirewallRule -Name 'RustDesk-LAN-Direct'
```

Direct IP ไม่ต้องพึ่งเซิร์ฟเวอร์เพื่อสร้าง session แต่โปรแกรมยังอาจติดต่อบริการภายนอกตาม configuration หากต้องการ local-only จริง ให้จำกัด outbound ที่ Firewall ขององค์กร และทดสอบโดยตัด Internet แต่คง LAN ไว้ อย่าใช้ Stop service เพื่อทำ offline เพราะจะหยุดรับ Direct IP ด้วย

## รันเซิร์ฟเวอร์ภายในเพื่อเชื่อมต่อด้วย ID

ใช้ Linux server หรือ Linux VM ที่ติดตั้ง Docker Engine และ Compose แล้ว ตัวอย่างเซิร์ฟเวอร์คือ `192.168.1.5` ขั้นตอนนี้เป็นการ deploy `rustdesk-server` ซึ่งเป็นคนละโปรเจกต์กับ client repo นี้

บน Linux สร้างโฟลเดอร์งานและไฟล์ `compose.yml`

```bash
mkdir -p rustdesk-local
cd rustdesk-local
```

ใส่เนื้อหาต่อไปนี้ใน `compose.yml` ตัวอย่างใช้ `latest` สำหรับทดลอง ก่อนใช้งานจริงให้ตรึงทั้งสอง image เป็น version หรือ digest ที่ทีมตรวจแล้ว

```yaml
services:
  hbbs:
    image: rustdesk/rustdesk-server:latest
    command: ["hbbs", "-r", "192.168.1.5:21117"]
    network_mode: host
    volumes:
      - ./data:/root
    depends_on:
      - hbbr
    restart: unless-stopped
  hbbr:
    image: rustdesk/rustdesk-server:latest
    command: hbbr
    network_mode: host
    volumes:
      - ./data:/root
    restart: unless-stopped
```

ตั้ง host Firewall ให้ยอมรับ TCP `21115–21117` และ UDP `21116` เฉพาะเครือข่ายหรือเครื่องที่อนุญาต ไม่ต้องเปิด TCP `21118–21119` ของเซิร์ฟเวอร์สำหรับ native client ในตัวอย่างนี้ ไม่ทำ port forwarding จาก Internet

เริ่มบริการและตรวจ log บน Linux

```bash
sudo docker compose up -d
sudo docker compose ps
sudo docker compose logs --tail=50 hbbs hbbr
sudo cat data/id_ed25519.pub
```

ใช้เฉพาะเนื้อหา `id_ed25519.pub` ตั้งค่า client ห้ามแจกไฟล์ private key `id_ed25519` จำกัดสิทธิ์และสำรองโฟลเดอร์ `data` เพราะมี key และข้อมูลของเซิร์ฟเวอร์

ตั้งค่าบน Windows ทั้งสองเครื่อง

1. เปิด **Settings > Network > ID/Relay server**
2. ตั้ง **ID server** เป็น `192.168.1.5`
3. ตั้ง **Relay server** เป็น `192.168.1.5:21117`
4. ตั้ง **Key** เป็น public key ที่อ่านจากเซิร์ฟเวอร์ผ่านช่องทางที่เชื่อถือได้ สำหรับ OSS ตัวอย่างนี้ให้เว้น **API server** ว่าง
5. ปิด **Enable direct IP access** เพราะต้องการใช้เส้นทาง ID ที่ตรวจสอบ key
6. รอให้ทั้งสองเครื่องลงทะเบียนกับเซิร์ฟเวอร์ภายใน แล้วใช้ **ID ของเครื่องปลายทาง** เชื่อมต่อ ห้ามกรอก IP ของเครื่องปลายทางแทน ID ในวิธีนี้
7. ตรวจไอคอนสถานะของ session และ tooltip ว่าเข้ารหัสแล้ว หากแจ้ง insecure หรือ key ไม่ตรง ให้หยุดเชื่อมต่อและแก้ configuration
8. ทดสอบการยืนยันตัวตนและสิทธิ์ที่ปิดไว้ แล้วตัด Internet โดยคง LAN เพื่อพิสูจน์ว่าใช้งานภายในได้

หากต้องตรวจ relay ให้เปิดตัวเลือกบังคับ relay ใน client ชั่วคราว เชื่อมต่อใหม่ และตรวจทั้งสถานะ session กับ log `hbbr` แล้วคืนค่าหลังทดสอบ

หยุดเซิร์ฟเวอร์โดยเก็บข้อมูลเดิมไว้

```bash
sudo docker compose down
```

## Build client จาก source บน Windows

ใช้ส่วนนี้เมื่อจำเป็นต้องรันโค้ดของ repo นี้ ไฟล์ release ทางการไม่ได้ยืนยันพฤติกรรมของ branch ที่แก้ไขเอง

ตรวจ prerequisites ก่อน build

- Rust MSVC toolchain และ Visual Studio C++ build tools พร้อม Windows SDK
- Flutter สำหรับ Windows desktop โดย Windows x64 ใน CI ของ checkout นี้ใช้ `3.24.5`
- Python, CMake, LLVM/Clang, NASM และ vcpkg ตามขั้นตอน Windows ใน CI
- vcpkg dependencies จาก `vcpkg.json` ใช้ triplet `x64-windows-static` และตั้ง `VCPKG_ROOT` ให้ถูกต้อง CI ของ checkout นี้ตรึง vcpkg ที่ `9e593bb18ea69cc5095e012465dcd675a822ed0d`
- ไฟล์ bridge จาก CI ที่ตรงกับ source และ Flutter ได้แก่ `src/bridge_generated.rs`, `src/bridge_generated.io.rs`, `flutter/lib/generated_bridge.dart` รวมถึงไฟล์อื่นใน artifact เดียวกัน คงโครงสร้าง directory ตามขั้นตอน restore ใน CI

เปิด shell ที่มี build tools แล้วเตรียม source

```powershell
Set-Location D:\Project\2569\rustdesk
git submodule update --init --recursive
flutter doctor -v
```

เมื่อ prerequisites และ bridge พร้อมแล้ว ใช้คำสั่ง build ตาม Windows CI

```powershell
python .\build.py --portable --flutter --skip-portable-pack --hwcodec
```

เปิดโปรแกรมที่ build ได้ โดยเก็บ DLL และโฟลเดอร์ `data` ที่มากับผล build ไว้ข้าง executable

```powershell
& .\flutter\build\windows\x64\runner\Release\rustdesk.exe
```

ค่าเริ่มต้นของ repo ให้ใช้ bridge จาก CI และไม่รัน `flutter_rust_bridge_codegen` ในเครื่อง สำหรับชุด CrhRustDesk นี้ผู้ใช้อนุญาตให้รันในเครื่องอย่างชัดเจนแล้ว ให้ใช้รุ่นที่ตรึงไว้ผ่าน [Generate-Bridge.ps1](../res/crhrustdesk/Generate-Bridge.ps1) อย่าใช้ `cargo run` เป็นทางลัดสำหรับ Flutter UI เพราะ README ส่วนดังกล่าวเป็นแนวทาง Sciter เดิม

ชุด CrhRustDesk มีเครื่องมือและวิธี build แยกไว้ใน [คู่มือ CrhRustDesk](../res/crhrustdesk/README.md) พร้อม [ขั้นตอนติดตั้งบน LAN](../res/crhrustdesk/LAN-SETUP-TH.md) การ build ผ่านไม่ใช่ผลทดสอบ session บนเครื่องปลายทาง

## เก็บหลักฐานก่อนส่งตรวจ security

ให้ทีม security ระบุเกณฑ์ที่ใช้ก่อนตัดสินว่าผ่าน แล้วทดสอบกับ binary และ configuration ที่จะใช้งานจริง

- ยืนยัน session เข้ารหัส และตรวจ traffic ตามเกณฑ์องค์กร
- ยืนยันว่าเครื่องที่ไม่อนุญาตและรหัสผ่านผิดเข้าควบคุมไม่ได้
- ยืนยันว่าความสามารถที่ปิดไว้ เช่น file transfer ใช้งานไม่ได้จริง
- ตรวจ Firewall และ outbound เพื่อยืนยันขอบเขต LAN-only
- ตรวจ dependencies และช่องโหว่ของ client กับ server รุ่นที่ใช้ รวมถึงทดสอบ EDR และ code signing ตามนโยบายองค์กร

สถานะปัจจุบันคือรองรับ LAN แต่ยังไม่มีหลักฐานเพียงพอที่จะรับรองว่าผ่าน security การตั้งเซิร์ฟเวอร์ภายในพร้อม key ไม่ได้แทนการตรวจเหล่านี้

## แหล่งอ้างอิง

- [FAQ ทางการเรื่อง Direct IP และการไม่เข้ารหัส](https://github.com/rustdesk/rustdesk/wiki/FAQ#i-only-use-rustdesk-for-a-few-devices-on-my-local-network-with-no-internet-connectivity-can-i-still-use-rustdesk-with-direct-ip-access)
- [ตัวเลือก Direct IP และพอร์ต](https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/)
- [รัน RustDesk Server OSS ด้วย Docker](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/)
- [ตั้งค่า client หลังติดตั้ง server](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/install/)
- [Windows build ใน repo](../.github/workflows/flutter-build.yml)
- [ขั้นตอน bridge ใน repo](../.github/workflows/bridge.yml)
- เส้นทาง Direct IP ในโค้ด: `Client::_start` ใน `src/client.rs`, `direct_server` ใน `src/rendezvous_mediator.rs` และ `identity_handshake` ใน `src/server.rs`

ดูขอบเขต runtime ที่เปลี่ยนเฉพาะ feature CrhRustDesk ในคู่มือ CrhRustDesk ที่ลิงก์ไว้ด้านบน
