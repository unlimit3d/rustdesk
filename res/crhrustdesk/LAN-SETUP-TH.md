# ติดตั้งชุด dev ที่ 172.29.0.52

เครื่อง dev ที่ใช้เป็น server คือ `172.29.0.96` ชุด client นี้ build ด้วยค่าเริ่มต้น loopback สำหรับทดสอบใน dev ใช้ Install.ps1 ด้านล่างเพื่อตั้งค่า LAN บนเครื่องปลายทาง

## เตรียมเครื่อง dev

เซิร์ฟเวอร์ API, ID และ relay เริ่มทำงานแล้ว HTTPS สำหรับ client อยู่ที่ `https://172.29.0.96:8443` ส่วนแผง admin ใช้ `http://127.0.0.1:21114/_admin/` บน dev เท่านั้น

ในการตรวจครั้งนี้ Windows Firewall บน dev ปิดทุก profile ต้องให้ผู้ดูแลตรวจและเปิดนโยบาย Firewall โดยคงการเข้าถึง RustDesk เดิมและบริการอื่นที่จำเป็นก่อน การเพิ่ม allow rule ขณะที่ Firewall ยังปิดไม่ได้จำกัดการเข้าถึงพอร์ต

เมื่อ profile Private เปิดแล้ว ให้ใช้ PowerShell แบบ Administrator บน dev เพื่ออนุญาตเฉพาะเครื่องปลายทาง

```powershell
D:\Project\2569\rustdesk\res\crhrustdesk\Open-DevLan.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools -ClientAddress 172.29.0.52
```

สคริปต์เปิด TCP `21115–21117`, UDP `21116` และ TCP `8443` ให้เฉพาะโปรแกรมเซิร์ฟเวอร์และ IP ที่ระบุ ไม่เปิด HTTP API `21114` หรือ WebSocket `21118–21119` และไม่เปลี่ยนสถานะ profile ให้ตรวจ existing rules ที่เปิดกว้างด้วย

หาก server หยุดอยู่ ให้เริ่มโดยระบุ IP สำหรับประกาศ ID/relay บน LAN แล้วเปิด TLS

```powershell
D:\Project\2569\rustdesk\res\crhrustdesk\Start-DevServer.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools -ServerAddress 172.29.0.96
D:\Project\2569\rustdesk\res\crhrustdesk\Start-DevTls.ps1 -ToolsRoot D:\Project\2569\CrhRustDesk-build-tools -ServerAddress 172.29.0.96
```

## ติดตั้งบนเครื่องปลายทาง

คัดลอกและแตกทั้ง ZIP ของชุด CrhRustDesk ไปที่ `172.29.0.52` ห้ามคัดลอกเฉพาะ executable เปิด PowerShell แบบ Administrator ในโฟลเดอร์ที่แตกไฟล์

HTTPS ในชุดทดลองใช้ CA ของ dev การติดตั้ง CA ลง LocalMachine Root ทำให้ทั้งเครื่องเชื่อถือ certificate ที่ CA นี้ออก ให้ผู้ดูแลตรวจ fingerprint ของไฟล์ที่ส่งมาผ่านช่องทางที่เชื่อถือได้ก่อน และใช้เฉพาะสภาพแวดล้อมทดลองที่ควบคุมเอง

```powershell
Get-FileHash .\CrhRustDesk-dev-root.crt -Algorithm SHA256
```

หลังผู้ดูแลตรวจและยอมรับ CA นี้แล้ว ให้ติดตั้ง certificate และแอป

```powershell
Import-Certificate -FilePath .\CrhRustDesk-dev-root.crt -CertStoreLocation Cert:\LocalMachine\Root
$key = (Get-Content -LiteralPath .\server-public-key.txt -Raw).Trim()
.\Install.ps1 -IdServer 172.29.0.96 -RelayServer 172.29.0.96:21117 -ApiServer https://172.29.0.96:8443 -PublicKey $key
```

Public key และ CA certificate ส่งให้ client ได้ ห้ามส่ง `id_ed25519`, `root.key`, JWT secret, database หรือไฟล์ credential ของ server

เปิดแอปที่ติดตั้งแล้ว ใช้ ID ของเครื่องปลายทางจากแอปเพื่อเชื่อมต่อ เครื่องควบคุมต้อง login บัญชีส่วนกลาง และเครื่องปลายทางต้องกดยอมรับตามค่าเริ่มต้น ตรวจสถานะ session ว่าเข้ารหัสแล้วก่อนใช้งาน

## เปิด Firewall บน Ubuntu 22 สำหรับวง LAN (UFW)

หากเซิร์ฟเวอร์เป็น Ubuntu 22 (เช่น `172.16.1.83`) และไม่ต้องการระบุ IP ปลายทางทีละเครื่อง ให้เปิดพอร์ตด้วย `ufw` ตามวง subnet ของ LAN ที่ใช้งานจริง (`172.29.0.0/24`, `172.16.0.0/16`, `10.0.0.0/8`)

```bash
# วง 172.29.0.0/24
sudo ufw allow from 172.29.0.0/24 to 172.16.1.83 port 21115:21117 proto tcp comment 'CrhRustDesk native LAN'
sudo ufw allow from 172.29.0.0/24 to 172.16.1.83 port 21116 proto udp comment 'CrhRustDesk discovery LAN'
sudo ufw allow from 172.29.0.0/24 to 172.16.1.83 port 8443 proto tcp comment 'CrhRustDesk HTTPS LAN'

# วง 172.16.0.0/16
sudo ufw allow from 172.16.0.0/16 to 172.16.1.83 port 21115:21117 proto tcp comment 'CrhRustDesk native LAN'
sudo ufw allow from 172.16.0.0/16 to 172.16.1.83 port 21116 proto udp comment 'CrhRustDesk discovery LAN'
sudo ufw allow from 172.16.0.0/16 to 172.16.1.83 port 8443 proto tcp comment 'CrhRustDesk HTTPS LAN'

# วง 10.0.0.0/8
sudo ufw allow from 10.0.0.0/8 to 172.16.1.83 port 21115:21117 proto tcp comment 'CrhRustDesk native LAN'
sudo ufw allow from 10.0.0.0/8 to 172.16.1.83 port 21116 proto udp comment 'CrhRustDesk discovery LAN'
sudo ufw allow from 10.0.0.0/8 to 172.16.1.83 port 8443 proto tcp comment 'CrhRustDesk HTTPS LAN'
```

หากต้องการเปิดพอร์ต Management `21120/tcp` ให้วง `10.0.0.0/8` ด้วย ให้เพิ่ม rule นี้

```bash
sudo ufw allow from 10.0.0.0/8 to 172.16.1.83 port 21120 proto tcp comment 'CrhRustDesk Management HTTPS'
```

ตรวจรายการทั้งหมดด้วย `sudo ufw status numbered` และหากเคยเปิด rule ราย IP ไว้เดิม ให้ลบจากเลขลำดับมากไปน้อยด้วย `sudo ufw delete <เลข>`

ยังไม่ได้ติดตั้งหรือทดสอบ session จริงที่ `172.29.0.52` และยังไม่มีผลตรวจ EDR, code signing หรือ pentest ตัว client ที่ build เองนี้ยังไม่มีลายเซ็นดิจิทัล
