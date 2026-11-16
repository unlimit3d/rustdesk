# เตรียม server Ubuntu ที่ 172.16.1.83

ชื่อบัญชีในคู่มือนี้เป็น placeholder สำหรับเผยแพร่ source คัดลอก `api.example.yaml` เป็น `api.yaml` และกำหนด AD bind identity เฉพาะเครื่อง ไฟล์ `api.yaml` จริงไม่อยู่ใน Git

เครื่องจริงชื่อ EverSyncGW ใช้ Ubuntu 22.04.5 LTS มี 4 vCPU, RAM ประมาณ 8 GiB, disk ว่างประมาณ 67 GiB มี Docker/API อื่นและ Nginx อยู่แล้ว ชุดนี้เตรียมเป็นบริการ systemd แยกเพื่อกำหนดพอร์ตและข้อมูลของ CrhRustDesk โดยไม่ต้องใช้ Docker image ที่ยังไม่ได้ build

สถานะ ณ 14 พฤศจิกายน 2569: ติดตั้งบริการทั้งห้าและตั้งให้เริ่มพร้อมเครื่องแล้ว API ใช้ strict AD patch และทดสอบ AD login จริงผ่าน เปิด Firewall เฉพาะ client `172.29.0.96` และ `172.29.0.52` ดูขั้นตอนใช้งานใน [OPERATIONS-TH.md](OPERATIONS-TH.md) รายการเตรียมด้านล่างเก็บไว้สำหรับติดตั้งเครื่องใหม่ ห้ามรันสคริปต์ติดตั้งทับระบบที่ใช้งานอยู่

## การเชื่อมต่อ

* Client → `https://172.16.1.83:8443` สำหรับบัญชีและ permit
* ID/Relay → TCP21115–21117 และ UDP21116
* Admin เต็มผ่าน LAN → `https://172.16.1.83:21120/_admin/` สำหรับ `172.16.0.0/16` และ `172.29.0.0/24`
* กำหนดสิทธิ์ remote ผ่าน LAN → `https://172.16.1.83:21120/_permissions/`
* API/admin → `127.0.0.1:21114` และ Management แบบ loopback → `127.0.0.1:21120` ผ่าน SSH tunnel
* API → `ldap://172.16.1.10:389` ด้วย `LDAP_READER@crhdomain.local` ตามคำสั่งผู้ใช้ ไม่มี TLS บนการเชื่อมต่อ LDAP นี้ ไม่ต้องแก้ DNS ของ host เพื่อค้นหา DC เพราะ config ใช้ IP

## ตั้งรหัสของบัญชีอ่าน AD

Login SSH ด้วยบัญชี Ubuntu แล้วรันจากโฟลเดอร์ staging:

```bash
bash ubuntu/set-ldap-secret.sh
```

กรอกรหัส sudo ของ Ubuntu เมื่อขอ จากนั้นกรอกรหัส AD ของ `LDAP_READER` ที่ prompt แยกกัน สคริปต์ไม่แสดงรหัสและเขียนเฉพาะ `/etc/crhrustdesk/ldap.env` แบบ root อ่านได้ ไม่ใส่รหัสใน source หรือชุดติดตั้ง client และไม่เริ่มบริการ หากไฟล์มีอยู่แล้วจะหยุดเพื่อไม่รีเซ็ตรหัสเดิม

## สิ่งที่ต้องทำก่อนเปิดบริการจริง

1. เมื่อผู้ใช้สั่ง build ให้ใช้ API source รุ่นที่ apply `../patches/rustdesk-api-ad-strict.patch` แล้ว ห้ามใช้ binary API เดิมเพื่อเปิด AD เพราะจะ fallback local password
2. เตรียม binary Linux ของ API/hbbs/hbbr/Caddy และ Python environment ของ account-server หลังตรวจเวอร์ชันและ checksum คำสั่ง build หรือสร้าง environment ยังไม่ได้รันในชุดนี้
3. สร้าง system user `crhrustdesk` พร้อมไดเรกทอรี `/opt/crhrustdesk`, `/etc/crhrustdesk` และ `/var/lib/crhrustdesk` ให้ executable/config เป็น root-owned และให้ service user เขียนได้เฉพาะ state ใต้ `/var/lib/crhrustdesk`
4. วาง API release รวม resources ที่ `/opt/crhrustdesk/api`, transport/Caddy ที่ `/opt/crhrustdesk/bin` และ account-server ที่ `/opt/crhrustdesk/account-server` วาง Python environment ที่ `/opt/crhrustdesk/permit-python` ใช้ requirements ของ account-server
5. เตรียม state `api`, `log`, `transport/x86_64`, `caddy` ภายใต้ `/var/lib/crhrustdesk` และให้ `/opt/crhrustdesk/api/data` ชี้ state `api` ใช้ config `api.yaml` และ Caddyfile ของชุดนี้ใน `/etc/crhrustdesk`
6. ก่อนย้ายฐานข้อมูลจาก dev ให้หยุดการเขียนหรือใช้ SQLite backup ที่ถูกต้อง อย่าคัดลอกฐานข้อมูลที่กำลังเขียนอยู่แบบไฟล์เดี่ยว กำหนดว่าจะใช้ key เดิมหรือแยก production key ก่อนสร้าง client รุ่นจริง คง JWT secret เดียวกันใน API และ hbbs ผ่าน `/etc/crhrustdesk/jwt.env` ซึ่งมี `RUSTDESK_API_JWT_KEY` และจำกัดสิทธิ์ root
7. สร้าง/ย้าย permit signing key และ public key รวมถึง `unattended-users.json` โดย private key อยู่เฉพาะ server การสร้าง client ต้องใช้ public key ที่ตรงกัน บริการ permit อ่าน peer DB ที่ `transport/x86_64/db_v2.sqlite3` แม้อยู่บน Linux เพราะใช้ layout ร่วมกับชุดเดิม
8. ติดตั้ง unit ทั้งห้า แล้วเริ่ม hbbs/hbbr และ API บน loopback ก่อน ตั้งรหัส `admin` สำหรับ production และทดสอบว่ารหัสเริ่มต้นเข้าไม่ได้แล้ว จึงเริ่ม permit และ proxy ตั้ง Firewall ให้รับเฉพาะเครือข่าย client ที่อนุญาต ไม่เปิด21114/21120 หรือ WebSocket21118/21119 สู่ LAN ในชุด native นี้ พอร์ต80 และบริการเดิมคงการตั้งค่าเดิม
9. จัดให้ client เชื่อถือ HTTPS certificate ของ proxy ชุดนี้ใช้ internal CA เพื่อเริ่มทดสอบ ไม่ติดตั้ง trust ลงเครื่องใดอัตโนมัติ Production สามารถเปลี่ยนเป็น certificate ขององค์กรได้
10. ทดสอบ AD Login ถูก/ผิด, บัญชี disabled, สิทธิ์ราย username/เครื่อง, การแจ้งเตือนปลายทาง และ reboot ก่อน cutover หยุด dev เมื่อเปลี่ยน client มายัง production แล้ว

สำหรับ Management ให้ forward local21120 และ API admin21114 ผ่าน SSH ไปยัง loopback ของ server แล้วเปิดเว็บด้วย `127.0.0.1` หน้า Management ตรวจ Host/Origin แบบ loopback ไม่มีการเปิด HTTP admin สู่ LAN

## ผลการเตรียมครั้งนี้

วาง source และสคริปต์ที่ `/home/SSH_USER/crhrustdesk-staging` และติดตั้ง runtime ใต้ `/opt/crhrustdesk` ด้วย service user แยก ข้อมูลใหม่อยู่ `/var/lib/crhrustdesk` โดยไม่ได้ย้ายฐานข้อมูลหรือ private key จาก dev ทดสอบ local recovery admin, AD login ด้วย `LDAP_READER`, token validation, Management สำหรับ admin และการปฏิเสธบัญชีทั่วไป/token ปลอม/คำขอ permit ที่ไม่มี token ผ่านแล้ว ยังไม่ได้ทดสอบบัญชี AD ที่ถูก disable หรือ remote desktop จริงบน `172.29.0.52` Container เดิมยังทำงาน ไม่เปลี่ยน DNS หรือ Nginx

ตรวจซ้ำบน server ได้ด้วยคำสั่งต่อไปนี้ โดยอ่าน secret ที่ตั้งไว้แล้ว:

```bash
sudo python3 -B /home/SSH_USER/crhrustdesk-staging/ubuntu/verify-ldap.py --bind-user LDAP_BIND_UPN --account LDAP_READER
```
