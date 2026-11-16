# ใช้ CrhRustDesk บน Ubuntu 172.16.1.83

บริการบน Ubuntu พร้อมทดสอบบัญชีแล้ว Client และตัวติดตั้ง Windows ที่ใช้กุญแจใหม่ของ Ubuntu build แล้วใน `target/CrhRustDesk-Ubuntu-Setup` อย่าใช้ตัวติดตั้ง dev เดิมเพื่อทดสอบสิทธิ์บน server นี้

## เข้า Management และกำหนดผู้ใช้

เปิด **https://172.16.1.83:21120/_admin/** จาก LAN `172.16.0.0/16` หรือ `172.29.0.0/24` เพื่อใช้หน้า Admin เต็มแบบ dev สำหรับผู้ใช้ log และเปลี่ยนรหัสผ่าน เปิด **https://172.16.1.83:21120/_permissions/** เพื่อกำหนดสิทธิ์ remote ทั้งสองหน้า Login ด้วย `admin` และรหัส CrhRustDesk ไม่ต้องเปิด SSH tunnel สำหรับวิธีนี้ ใช้เครื่องที่เชื่อถือ CA ภายในของ Ubuntu แล้ว พอร์ตนี้ให้บริการ HTTPS เท่านั้น

เปลี่ยนรหัส local `admin` ที่หน้า Admin เต็มใน **User Info → Password → Change Password** บันทึกแล้วให้ออกจากระบบและ Login ใหม่ด้วยรหัสใหม่ ไฟล์ `admin-initial-password` ไม่เปลี่ยนตามรหัสใหม่ บัญชี AD เปลี่ยนรหัสที่ AD

หากต้องการใช้ loopback เดิม ให้ทำตามขั้นตอน SSH tunnel ต่อไปนี้:

1. ใช้เครื่อง IT ที่พอร์ต local `21120` และ `21114` ว่าง เครื่อง dev ปัจจุบันมีบริการเดิมครองพอร์ตเหล่านี้อยู่ อย่าหยุด process อื่นโดยไม่ตรวจชื่อบริการ
2. เปิด PowerShell แล้วคง SSH tunnel นี้ไว้ระหว่างใช้งาน

```powershell
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:21120:127.0.0.1:21120 -L 127.0.0.1:21114:127.0.0.1:21114 SSH_USER@172.16.1.83
```

3. เปิด SSH อีกหน้าต่าง แล้วอ่านรหัสเริ่มต้นจากไฟล์ส่วนตัวบน server อย่าส่งรหัสกลับมาในแชต

```powershell
ssh -t SSH_USER@172.16.1.83 "sudo cat /etc/crhrustdesk/admin-initial-password"
```

4. เปิด `http://127.0.0.1:21120/_admin/` แล้ว Login ด้วย `admin` และรหัสที่อ่านจากไฟล์ บัญชี Ubuntu `SSH_USER` ใช้สำหรับ SSH ส่วนบัญชี `admin` ใช้จัดการ CrhRustDesk
5. ระบุ username ของ AD แบบ `sAMAccountName` เช่น `AD_USERNAME` แล้วเลือกทุกเครื่องหรือระบุ ID ของเครื่อง กดบันทึก การกำหนดสิทธิ์นี้ไม่ทำให้ผู้ใช้เป็น admin
6. หลัง client ใหม่พร้อม ให้ผู้ใช้ Login ด้วย username ของ AD และรหัส AD บนเครื่อง IT ไม่ต้องตั้งรหัส AD ซ้ำใน CrhRustDesk

การติดตั้งใหม่อนุญาต recovery admin ส่วนสิทธิ์ของบัญชี AD ให้ผู้ดูแลกำหนดใน Management ค่า `AD_USERNAME`, `SSH_USER` และ `LDAP_READER` ในคู่มือนี้เป็น placeholder ไม่ใช่ชื่อบัญชีจริง บัญชีอ่าน AD ไม่ได้รับสิทธิ์ remote อัตโนมัติ รายชื่อ AD ที่ยังไม่เคย Login อาจยังไม่ปรากฏในรายการ ให้พิมพ์ username โดยตรง

หน้า API admin อยู่ `http://127.0.0.1:21114/_admin/` ผ่าน tunnel เดียวกัน เปลี่ยนรหัส `admin` ในหน้าโปรไฟล์หลังเข้าใช้งานครั้งแรก ไฟล์ initial password จะไม่เปลี่ยนตามรหัสใหม่

## เตรียมเครื่องปลายทางเมื่อมีตัวติดตั้งใหม่

1. รับตัวติดตั้งที่ผู้ดูแล build สำหรับ server `172.16.1.83` และ permit public key ชุดนี้
2. บน Windows 10 หรือ 11 x64 เปิดตัวติดตั้งด้วยสิทธิ์ Administrator
3. เลือกบทบาทเครื่องปลายทางสำหรับรับ remote เข้า หรือบทบาทเครื่อง IT สำหรับ remote ออก
4. ตรวจ server `172.16.1.83` และ Account API `https://172.16.1.83:8443` ก่อนยอมรับ CA ภายใน
5. บนเครื่องปลายทาง รอให้ลงทะเบียนกับ server แล้วส่ง ID ให้ผู้ดูแลกำหนดสิทธิ์ใน Management
6. บนเครื่อง IT Login บัญชี AD แล้วใส่ ID หรือ IP ปลายทาง เช่น `172.29.0.52` บัญชีที่ได้รับสิทธิ์เข้า desktop ได้พร้อมการแจ้งเตือนปลายทาง ยังต้องผ่าน 2FA หากปลายทางเปิดไว้

บทบาทเครื่องปลายทางใน source รุ่นใหม่ต้องมี permit ส่วนกลาง บัญชีที่ไม่ได้รับสิทธิ์จะถูกปฏิเสธ การรับส่งไฟล์แยก session, terminal และ tunnel ยังไม่รวมในสิทธิ์ desktop นี้ การทดสอบภาพหน้าจอ เมาส์ คีย์บอร์ด และการแจ้งเตือนบนเครื่องจริงยังรอ client ใหม่

## ตรวจและดูแลบริการ

บน Ubuntu ตรวจทั้งห้าบริการด้วยคำสั่งนี้

```bash
systemctl is-active crhrustdesk-hbbs crhrustdesk-hbbr crhrustdesk-api crhrustdesk-permit crhrustdesk-proxy
sudo python3 -B /home/SSH_USER/crhrustdesk-staging/ubuntu/verify-ldap.py --bind-user LDAP_BIND_UPN --account LDAP_READER
```

ผลปกติของคำสั่งแรกคือ `active` ห้าบรรทัด เปิดให้เริ่มพร้อมเครื่องแล้ว แต่ยังไม่ได้ reboot host เพราะมีบริการอื่นร่วมใช้งาน หลังเปลี่ยนรหัส admin แล้ว `verify-api.py` จะใช้ไฟล์ initial password เดิมไม่ได้

Client ที่อนุญาตตอนนี้คือ `172.29.0.96` และ `172.29.0.52` ใช้ TCP `21115` ถึง `21117`, UDP `21116` และ HTTPS TCP `8443` บน Ubuntu หากเพิ่มเครื่องอื่น ให้เพิ่ม source IP ใน UFW ด้วย API `21114` และ Python backend `21120` ฟังเฉพาะ loopback ส่วน Caddy เปิด Management HTTPS ที่ `172.16.1.83:21120` ให้สอง subnet ข้างต้น พอร์ต `21118` และ `21119` ของ transport server ไม่เปิดผ่าน UFW

Direct IP ใช้ TCP `21118` บนเครื่องปลายทาง Windows ซึ่งเป็นคนละเครื่องกับ Ubuntu ต้องมี firewall rule ที่ปลายทางอนุญาต IP เครื่อง IT ชุด installer ปัจจุบันตั้งค่าเครื่อง IT เป็น `172.29.0.96`

เก็บ config และ secret ที่ `/etc/crhrustdesk` เก็บฐานข้อมูลกับ private key ที่ `/var/lib/crhrustdesk` สำรองสอง directory นี้แบบเข้ารหัสและจำกัดผู้เข้าถึง ใช้ SQLite backup หรือหยุดบริการ CrhRustDesk ก่อนสำรองฐานข้อมูล อย่าคัดลอกเฉพาะไฟล์ฐานข้อมูลที่กำลังเขียนอยู่

การเชื่อมต่อ AD ใช้ LDAP ปกติไป `172.16.1.10:389` ตามที่กำหนด จึงไม่มีการเข้ารหัสรหัสผ่านระหว่าง Ubuntu กับ AD ยังไม่ใช่ผลรับรอง security ขององค์กร

## ตรวจ CA และไฟล์ build

Public key และ CA สำหรับ build อยู่บนเครื่อง dev ที่ `D:\Project\2569\CrhRustDesk-build-tools\ubuntu-server` ไม่มี private key ใน directory นี้

SHA-256 ของไฟล์ `CrhRustDesk-Ubuntu-root.crt` คือ

```text
38441E1FCC1EE29CFADD0F25F97F9A33875CDECAB4569BE8C26288A00F1AF351
```

การตรวจ HTTPS จาก dev ใช้ CA ใบนี้โดยไม่ติดตั้งลง trust store ผ่านแล้ว Windows curl แบบ Schannel รายงานว่าไม่ทราบสถานะ revocation ของ CA ภายใน จึงตรวจซ้ำด้วย Python/OpenSSL ซึ่งตรวจ chain และชื่อ IP ผ่าน ไม่ได้ใช้ตัวเลือกข้ามการตรวจ certificate

API Linux ที่ติดตั้งมี SHA-256 `eb51e1f9a207a528b0152e60851d82cd9624e1007dd36cd3a0d2d0943941d707` สร้างจาก API v2.7 พร้อม strict AD patch ด้วย Go 1.27.4 ส่วน client Windows รุ่นใหม่ build ตามคำสั่งผู้ใช้แล้ว ตรวจ embedded public keys, CA, DLL ของ bundle และ `--version` ผ่าน ยังรอติดตั้งและทดสอบ remote บนเครื่องจริง
