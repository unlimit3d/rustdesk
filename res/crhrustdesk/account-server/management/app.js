'use strict';
let token = '';
const element = (id) => document.getElementById(id);
const status = (message) => { element('status').textContent = message; };

async function request(action, body) {
  const response = await fetch('/crhrustdesk/admin/' + action, {
    method: 'POST', headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token},
    body: JSON.stringify(body), cache: 'no-store',
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'ดำเนินการไม่สำเร็จ');
  return data;
}

function editUser(user) {
  element('grant-user').value = user.username;
  element('enabled').checked = user.devices.length > 0;
  element('all-devices').checked = user.devices.includes('*');
  element('device-ids').value = user.devices.filter((id) => id !== '*').join(', ');
}

async function loadUsers() {
  const data = await request('users', {search: element('search').value});
  element('admin-policy').textContent = data.allow_admin ? 'นโยบายปัจจุบันอนุญาตบัญชี administrator ทุกเครื่องโดยอัตโนมัติ' : 'บัญชี administrator ต้องมีสิทธิ์ราย username เช่นเดียวกับผู้ใช้อื่น';
  element('users').replaceChildren();
  for (const user of data.users) {
    const row = document.createElement('tr');
    for (const value of [user.username, user.is_admin && data.allow_admin ? 'Administrator: ทุกเครื่อง' : user.devices.includes('*') ? 'ทุกเครื่อง' : user.devices.join(', ') || 'ยังไม่ได้อนุญาต']) {
      const cell = document.createElement('td');
      cell.textContent = value;
      row.appendChild(cell);
    }
    const cell = document.createElement('td');
    const button = document.createElement('button');
    button.type = 'button'; button.textContent = 'เลือก';
    button.disabled = user.is_admin && data.allow_admin;
    button.addEventListener('click', () => editUser(user));
    cell.appendChild(button); row.appendChild(cell);
    element('users').appendChild(row);
  }
}

element('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    const data = await request('login', {username: element('login-user').value, password: element('login-password').value});
    token = data.access_token;
    element('login-password').value = '';
    element('login-panel').hidden = true;
    element('access-panel').hidden = false;
    await loadUsers(); status('เข้าสู่ระบบแล้ว: ' + data.name);
  } catch (error) { status(error.message); }
});

element('search-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  try { await loadUsers(); status('แสดงไม่เกิน 100 บัญชี ใช้ช่องค้นหาเพื่อจำกัดผลลัพธ์'); }
  catch (error) { status(error.message); }
});

element('grant-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const devices = !element('enabled').checked ? [] : element('all-devices').checked ? ['*'] :
    element('device-ids').value.split(',').map((id) => id.trim()).filter(Boolean);
  if (element('enabled').checked && devices.length === 0) { status('เลือกทุกเครื่อง หรือระบุ ID เครื่องปลายทาง'); return; }
  try {
    const username = element('grant-user').value.trim();
    await request('grant', {username, devices});
    await loadUsers(); status('บันทึกสิทธิ์ของ ' + username + ' แล้ว');
  } catch (error) { status(error.message); }
});

element('logout').addEventListener('click', () => {
  token = ''; element('access-panel').hidden = true; element('login-panel').hidden = false;
  element('users').replaceChildren(); status('ออกจากระบบแล้ว');
});
