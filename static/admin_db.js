// === Глобальные карты сопоставления ===
const uchastokToDeputatId = new Map();
const deputatIdToUchastok = new Map();

// === Управление вкладками ===
function showSection(section) {
    const sections = ['deputats', 'addresses', 'topics', 'appeals', 'campaigns'];
    sections.forEach(s => {
        const secEl = document.getElementById(`section${s.charAt(0).toUpperCase() + s.slice(1)}`);
        const tabEl = document.getElementById(`tab${s.charAt(0).toUpperCase() + s.slice(1)}`);
        if (secEl) secEl.style.display = s === section ? 'block' : 'none';
        if (tabEl) tabEl.style.background = s === section ? '#3498db' : '#95a5a6';
    });
}

// === Универсальный поиск ===
function attachSearch(inputId, tableId, fields) {
    const input = document.getElementById(inputId);
    if (!input) return;
    input.addEventListener('input', function() {
        const search = this.value.toLowerCase();
        document.querySelectorAll(`#${tableId} tbody tr`).forEach(row => {
            const visible = fields.some(f => (row.dataset[f]?.toLowerCase() || '').includes(search));
            row.style.display = visible ? '' : 'none';
        });
    });
}

// === Инициализация данных при загрузке ===
document.addEventListener('DOMContentLoaded', () => {
    attachSearch('searchDeputats', 'deputatsTable', ['fio', 'uchastok']);
    attachSearch('searchAddresses', 'addressesTable', ['street', 'house']);
    attachSearch('searchAppeals', 'appealsTable', ['fio', 'topic', 'status']);

    // Построение карт участок <-> ID депутата
    document.querySelectorAll('#deputatsTable tbody tr').forEach(row => {
        const id = row.dataset.id;
        const uch = String(row.dataset.uchastok);
        if (id && uch) {
            uchastokToDeputatId.set(uch, id);
            deputatIdToUchastok.set(id, uch);
        }
    });

    // Заполнение выпадающих списков участками
    const uchSelects = ['new_app_uch', 'new_camp_uch'];
    const uniqueUch = [...new Set(uchastokToDeputatId.keys())].sort((a, b) => a - b);
    uchSelects.forEach(selId => {
        const sel = document.getElementById(selId);
        if (sel) {
            sel.innerHTML = '<option value="">Выберите участок</option>';
            uniqueUch.forEach(u => sel.add(new Option(u, u)));
        }
    });

    // Заполнение списка темами
    const topicSel = document.getElementById('new_app_topic');
    if (topicSel) {
        topicSel.innerHTML = '<option value="">Выберите тему</option>';
        document.querySelectorAll('#topicsTable tbody tr').forEach(row => {
            if (row.dataset.name) topicSel.add(new Option(row.dataset.name, row.dataset.name));
        });
    }

    // Проставление участков в таблице инициатив
    document.querySelectorAll('#campaignsTable tbody tr').forEach(row => {
        const rowId = row.dataset.rowId;
        const depId = row.dataset.deputatId;
        const uchInput = document.getElementById(`camp_uch_${rowId}`);
        if (uchInput && depId) {
            uchInput.value = deputatIdToUchastok.get(String(depId)) || '';
        }
    });
});

// === CRUD: Депутаты ===
async function updateDeputat(id) {
    const payload = {
        fio: document.getElementById(`fio_${id}`)?.value,
        birth_date: document.getElementById(`birth_${id}`)?.value,
        education: document.getElementById(`edu_${id}`)?.value,
        experience: document.getElementById(`exp_${id}`)?.value,
        phone: document.getElementById(`phone_${id}`)?.value,
        email: document.getElementById(`email_${id}`)?.value,
        reception_address: document.getElementById(`address_${id}`)?.value,
        biography: document.getElementById(`bio_${id}`)?.value,
        password: document.getElementById(`password_${id}`)?.value || ''
    };
    try {
        const res = await fetch(`/super-admin/deputat/${id}`, {
            method: 'PUT', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (res.ok) {
            alert(payload.password ? 'Обновлено!\n⚠️ Пароль изменён.' : 'Обновлено');
            location.reload();
        } else {
            alert('Ошибка бэкенда: ' + (data.error || res.statusText));
        }
    } catch (e) { alert('Ошибка сети'); console.error(e); }
}

async function deleteDeputat(id) {
    if (!confirm('Удалить депутата?')) return;
    const res = await fetch(`/super-admin/deputat/${id}`, { method: 'DELETE' });
    alert(res.ok ? 'Удалено' : 'Ошибка');
    if (res.ok) location.reload();
}

async function addDeputat() {
    const user_id = Number(document.getElementById('new_user_id').value);
    const uchastok = Number(document.getElementById('new_uchastok').value);
    const fio = document.getElementById('new_fio').value.trim();
    const password = document.getElementById('new_password').value;
    const bio = document.getElementById('new_bio').value.trim();

    if (isNaN(user_id) || isNaN(uchastok) || !fio) return alert('Заполните ID, Участок и ФИО');
    if (!password) return alert('Укажите пароль');

    const res = await fetch('/super-admin/deputat', { 
        method: 'POST', headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify({ user_id, uchastok, fio, password, biography: bio }) 
    });
    const data = await res.json();
    if (res.ok) { alert('Добавлено'); location.reload(); } 
    else { alert('Ошибка: ' + (data.error || res.statusText)); }
}

// === CRUD: Адреса ===
async function updateAddress(id) {
    const payload = {
        uchastok: Number(document.getElementById(`addr_uch_${id}`).value),
        street: document.getElementById(`addr_street_${id}`).value,
        house_number: document.getElementById(`addr_house_${id}`).value
    };
    const res = await fetch(`/super-admin/address/${id}`, { method: 'PUT', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload) });
    alert(res.ok ? 'Обновлено' : 'Ошибка');
    if (res.ok) location.reload();
}

async function deleteAddress(id) {
    if (!confirm('Удалить адрес?')) return;
    const res = await fetch(`/super-admin/address/${id}`, { method: 'DELETE' });
    alert(res.ok ? 'Удалено' : 'Ошибка');
    if (res.ok) location.reload();
}

async function addAddress() {
    const uch = Number(document.getElementById('new_addr_uch').value);
    const street = document.getElementById('new_addr_street').value.trim();
    const house = document.getElementById('new_addr_house').value.trim();
    if (isNaN(uch) || !street || !house) return alert('Заполните все поля');
    const res = await fetch('/super-admin/address', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ uchastok: uch, street, house_number: house }) });
    alert(res.ok ? 'Добавлено' : 'Ошибка');
    if (res.ok) location.reload();
}

// === CRUD: Темы ===
async function updateTopic(id) {
    const res = await fetch(`/super-admin/topic/${id}`, {
        method: 'PUT', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({ topic_name: document.getElementById(`topic_name_${id}`).value })
    });
    alert(res.ok ? 'Обновлено' : 'Ошибка');
    if (res.ok) location.reload();
}

async function deleteTopic(id) {
    if (!confirm('Удалить тему?')) return;
    const res = await fetch(`/super-admin/topic/${id}`, { method: 'DELETE' });
    alert(res.ok ? 'Удалено' : 'Ошибка');
    if (res.ok) location.reload();
}

async function addTopic() {
    const name = document.getElementById('new_topic_name').value.trim();
    if (!name) return alert('Введите название темы');
    const res = await fetch('/super-admin/topic', {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({ topic_name: name })
    });
    alert(res.ok ? 'Добавлено' : 'Ошибка');
    if (res.ok) location.reload();
}

// === CRUD: Обращения ===
async function updateAppeal(id) {
    const payload = {
        uchastok: Number(document.getElementById(`app_uch_${id}`).value),
        topic: document.getElementById(`app_topic_${id}`).value,
        fio: document.getElementById(`app_fio_${id}`).value,
        phone: document.getElementById(`app_phone_${id}`).value,
        email: document.getElementById(`app_email_${id}`).value,
        need_visit: document.getElementById(`app_visit_${id}`).checked,
        status: document.getElementById(`app_status_${id}`).value,
        result_text: document.getElementById(`app_result_${id}`).value
    };
    const res = await fetch(`/super-admin/appeal/${id}`, { method: 'PUT', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload) });
    alert(res.ok ? 'Обновлено' : 'Ошибка');
    if (res.ok) location.reload();
}

async function deleteAppeal(id) {
    if (!confirm('Удалить обращение?')) return;
    const res = await fetch(`/super-admin/appeal/${id}`, { method: 'DELETE' });
    alert(res.ok ? 'Удалено' : 'Ошибка');
    if (res.ok) location.reload();
}

async function addAppeal() {
    const uch = Number(document.getElementById('new_app_uch').value);
    const topic = document.getElementById('new_app_topic').value;
    const fio = document.getElementById('new_app_fio').value.trim();
    const phone = document.getElementById('new_app_phone').value.trim();
    const email = document.getElementById('new_app_email').value.trim();
    const text = document.getElementById('new_app_text').value.trim();

    if (isNaN(uch) || !topic || !fio || !text) return alert('Заполните Участок, Тему, ФИО и Текст обращения');
    const res = await fetch('/super-admin/appeal', { 
        method: 'POST', headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify({ uchastok: uch, topic, fio, phone, email, text, need_visit: false, status: 'Новое' }) 
    });
    const data = await res.json();
    if (res.ok) { alert('Добавлено'); location.reload(); } 
    else { alert('Ошибка: ' + (data.error || res.statusText)); }
}

// === CRUD: Инициативы ===
async function updateCampaign(rowId) {
    const uch = String(document.getElementById(`camp_uch_${rowId}`).value).trim();
    const deputatId = uchastokToDeputatId.get(uch);
    if (!deputatId) return alert(`Депутат с участком "${uch}" не найден в базе!`);
    const text = document.getElementById(`camp_text_${rowId}`).value.trim();
    if (!text) return alert('Текст инициативы не может быть пустым');

    const payload = {
        deputat_id: parseInt(deputatId),
        text: text,
        votes_for: parseInt(document.getElementById(`camp_for_${rowId}`).value) || 0,
        votes_against: parseInt(document.getElementById(`camp_against_${rowId}`).value) || 0
    };
    const res = await fetch(`/super-admin/campaign/${rowId}`, { method: 'PUT', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload) });
    const data = await res.json();
    if (res.ok) { alert('Обновлено'); location.reload(); } 
    else { alert('Ошибка: ' + (data.error || res.statusText)); }
}

async function deleteCampaign(id) {
    if (!confirm('Удалить инициативу?')) return;
    const res = await fetch(`/super-admin/campaign/${id}`, { method: 'DELETE' });
    alert(res.ok ? 'Удалено' : 'Ошибка');
    if (res.ok) location.reload();
}

async function addCampaign() {
    const uch = String(document.getElementById('new_camp_uch').value).trim();
    const deputatId = uchastokToDeputatId.get(uch);
    if (!deputatId) return alert(`Депутат с участком "${uch}" не найден в базе!`);
    const text = document.getElementById('new_camp_text').value.trim();
    if (!text) return alert('Введите текст инициативы');

    const payload = {
        deputat_id: parseInt(deputatId),
        text: text,
        votes_for: 0, votes_against: 0
    };
    const res = await fetch('/super-admin/campaign', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload) });
    const data = await res.json();
    if (res.ok) { alert('Добавлено'); location.reload(); } 
    else { alert('Ошибка: ' + (data.error || res.statusText)); }
}

// === Загрузка фото ===
async function uploadPhoto(id) {
    const tempInput = document.createElement('input');
    tempInput.type = 'file'; tempInput.accept = 'image/*';
    tempInput.onchange = async function() {
        const file = tempInput.files[0];
        if (!file) return alert('Выберите файл');
        if (!file.type.match('image.*')) return alert('Только изображения (PNG, JPG, JPEG, GIF)');
        const formData = new FormData(); formData.append('photo', file);
        try {
            const res = await fetch(`/super-admin/deputat/${id}/photo`, { method: 'POST', body: formData });
            const data = await res.json();
            if (res.ok) { alert('Фото загружено!'); location.reload(); }
            else { alert('Ошибка: ' + (data.error || res.statusText)); }
        } catch (e) { alert('Ошибка сети'); console.error(e); }
    };
    tempInput.click();
}