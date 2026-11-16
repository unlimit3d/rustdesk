# ตรวจข้อมูลลับก่อน commit

Config ที่ใช้งานจริงและข้อมูลบัญชีต้องอยู่นอก Git ใช้ `ubuntu/api.example.yaml` เป็นแบบ แล้วสร้าง `ubuntu/api.yaml` เฉพาะเครื่อง ไฟล์จริงถูก ignore ไว้ คำว่า `SSH_USER`, `AD_USERNAME`, `LDAP_READER` และ `LDAP_BIND_UPN` ในคู่มือเป็น placeholder ให้แทนค่าจริงเฉพาะตอนใช้งาน

ห้าม commit ไฟล์รหัสผ่าน `.env`, credential XML, private key, signing key, certificate ที่ใช้จริง, public-key files ของ deployment และข้อมูล runtime ไฟล์เหล่านี้มีทั้งกฎ ignore และกฎตรวจชื่อไฟล์ก่อน commit การใส่ใน `.gitignore` ไม่ลบไฟล์ที่เคยถูกติดตามหรือ commit ไปแล้ว

## ตรวจและเปิดใช้งาน

บนเครื่องนี้ติดตั้ง Gitleaks 8.30.1 จาก release ต้นทางและตรวจ SHA-256 กับรายการ checksum แล้ว เปิด pre-commit hook เฉพาะ repo นี้ไว้แล้ว โดยไม่ได้ stage, commit หรือ push ไฟล์ใด

เมื่อ clone บนเครื่องอื่น ให้ติดตั้ง Gitleaks จาก [แหล่งต้นทาง](https://github.com/gitleaks/gitleaks) แล้วเปิด hook:

```powershell
.\res\crhrustdesk\Enable-SecretCheck.ps1 -Gitleaks 'C:\Tools\gitleaks.exe'
```

ตรวจไฟล์ที่อาจจะนำขึ้น Git และตรวจ index ก่อน commit:

```powershell
python res/crhrustdesk/Check-GitSecrets.py --worktree
git diff --cached --stat
python res/crhrustdesk/Check-GitSecrets.py --staged
```

ตัวตรวจ staged อ่าน blob จาก Git index จริง การแก้รหัสออกจาก working tree หลัง `git add` ยังไม่ทำให้ staged version สะอาด ต้องแก้แล้ว stage ไฟล์ใหม่ด้วย ตัวตรวจไม่พิมพ์ค่าลับออกมา

การตรวจใช้กฎมาตรฐาน Gitleaks พร้อมการตรวจ private key, serialized credential และชื่อไฟล์อ่อนไหว บนเครื่องนี้มีรายการ hash ของค่าบัญชีและ credential ของ deployment อยู่นอก repo โดยเก็บ path เฉพาะใน local Git config ไม่มีค่าจริงอยู่ใน source ของตัวตรวจ

`secret-scan-baseline.json` ยกเว้นเฉพาะ source span เดิมที่ตรวจแล้วว่าเป็น dummy key ใน parser tests และ public example key ในข้อความแปลของ upstream ถ้าข้อความนั้นเปลี่ยน hash จะไม่ตรงและต้องตรวจใหม่ ไม่ยกเว้นทั้งไฟล์หรือทั้ง directory

## เมื่อพบข้อมูลลับ

1. หยุด commit และนำค่าจริงออกจากไฟล์ที่จะ commit
2. เก็บ config จริงในไฟล์ที่ถูก ignore หรือที่เก็บส่วนตัวนอก repo
3. ตรวจ staged version อีกครั้งก่อน commit
4. หากเคย push credential จริงแล้ว ให้เพิกถอนหรือเปลี่ยน credential นั้น การลบออกจากไฟล์ล่าสุดไม่ลบค่าจากประวัติ Git

Hook เป็นตัวป้องกันในเครื่องและผู้ใช้สามารถข้ามได้ จึงยังต้องตรวจ diff และกำหนด secret/push protection ฝั่ง Git hosting ตามนโยบายองค์กร การตรวจครั้งนี้ไม่ได้ rewrite ประวัติ Git หรือรับรองว่าประวัติ upstream ทั้งหมดไม่มีข้อมูลลับ
