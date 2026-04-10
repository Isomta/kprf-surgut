function showSection(section) {
    document.getElementById('sectionDeputats').style.display = section === 'deputats' ? 'block' : 'none';
    document.getElementById('sectionAddresses').style.display = section === 'addresses' ? 'block' : 'none';
    document.getElementById('sectionTopics').style.display = section === 'topics' ? 'block' : 'none';
    document.getElementById('tabDeputats').style.background = section === 'deputats' ? '#3498db' : '#95a5a6';
    document.getElementById('tabAddresses').style.background = section === 'addresses' ? '#3498db' : '#95a5a6';
    document.getElementById('tabTopics').style.background = section === 'topics' ? '#3498db' : '#95a5a6';
}

// Поиск по депутатам
if (document.getElementById('searchDeputats')) {
    document.getElementById('searchDeputats').addEventListener('input', function() {
        const search = this.value.toLowerCase();
        document.querySelectorAll('#deputatsTable tbody tr').forEach(row => {
            const fio = row.dataset.fio?.toLowerCase() || '';
            const uch = row.dataset.uchastok?.toString() || '';
            row.style.display = fio.includes(search) || uch.includes(search) ? '' : 'none';
        });
    });
}

// Поиск по адресам
if (document.getElementById('searchAddresses')) {
    document.getElementById('searchAddresses').addEventListener('input', function() {
        const search = this.value.toLowerCase();
        document.querySelectorAll('#addressesTable tbody tr').forEach(row => {
            const street = row.dataset.street?.toLowerCase() || '';
            const house = row.dataset.house?.toLowerCase() || '';
            row.style.display = street.includes(search) || house.includes(search) ? '' : 'none';
        });
    });
}

// CRUD Депутаты
async function updateDeputat(id) {
    const data = {
        fio: document.getElementById(`fio_${id}`).value,
        birth_date: document.getElementById(`birth_${id}`).value,
        education: document.getElementById(`edu_${id}`).value,
        experience: document.getElementById(`exp_${id}`).value,
        phone: document.getElementById(`phone_${id}`).value,
        reception_address: document.getElementById(`address_${id}`).value
    };
    const response = await fetch(`/super-admin/deputat/${id}`, {
        method: 'PUT', 
        headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify(data)
    });
    alert(response.ok ? 'Обновлено' : 'Ошибка');
    if (response.ok) location.reload();
}

async function deleteDeputat(id) {
    if (!confirm('Удалить депутата?')) return;
    const response = await fetch(`/super-admin/deputat/${id}`, { method: 'DELETE' });
    alert(response.ok ? 'Удалено' : 'Ошибка');
    if (response.ok) location.reload();
}

async function addDeputat() {
    const data = {
        user_id: parseInt(document.getElementById('new_user_id').value),
        uchastok: parseInt(document.getElementById('new_uchastok').value),
        fio: document.getElementById('new_fio').value,
        password: document.getElementById('new_password').value,
        birth_date: '', 
        education: '', 
        experience: '', 
        reception_address: '', 
        phone: '', 
        email: ''
    };
    const response = await fetch('/super-admin/deputat', {
        method: 'POST', 
        headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify(data)
    });
    alert(response.ok ? 'Добавлено' : 'Ошибка');
    if (response.ok) location.reload();
}

// CRUD Адреса
async function updateAddress(id) {
    const data = {
        uchastok: parseInt(document.getElementById(`addr_uch_${id}`).value),
        street: document.getElementById(`addr_street_${id}`).value,
        house_number: document.getElementById(`addr_house_${id}`).value
    };
    const response = await fetch(`/super-admin/address/${id}`, {
        method: 'PUT', 
        headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify(data)
    });
    alert(response.ok ? 'Обновлено' : 'Ошибка');
    if (response.ok) location.reload();
}

async function deleteAddress(id) {
    if (!confirm('Удалить адрес?')) return;
    const response = await fetch(`/super-admin/address/${id}`, { method: 'DELETE' });
    alert(response.ok ? 'Удалено' : 'Ошибка');
    if (response.ok) location.reload();
}

async function addAddress() {
    const data = {
        uchastok: parseInt(document.getElementById('new_addr_uch').value),
        street: document.getElementById('new_addr_street').value,
        house_number: document.getElementById('new_addr_house').value
    };
    const response = await fetch('/super-admin/address', {
        method: 'POST', 
        headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify(data)
    });
    alert(response.ok ? 'Добавлено' : 'Ошибка');
    if (response.ok) location.reload();
}

// CRUD Темы
async function updateTopic(id) {
    const data = { topic_name: document.getElementById(`topic_name_${id}`).value };
    const response = await fetch(`/super-admin/topic/${id}`, {
        method: 'PUT', 
        headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify(data)
    });
    alert(response.ok ? 'Обновлено' : 'Ошибка');
    if (response.ok) location.reload();
}

async function deleteTopic(id) {
    if (!confirm('Удалить тему?')) return;
    const response = await fetch(`/super-admin/topic/${id}`, { method: 'DELETE' });
    alert(response.ok ? 'Удалено' : 'Ошибка');
    if (response.ok) location.reload();
}

async function addTopic() {
    const data = { topic_name: document.getElementById('new_topic_name').value };
    const response = await fetch('/super-admin/topic', {
        method: 'POST', 
        headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify(data)
    });
    alert(response.ok ? 'Добавлено' : 'Ошибка');
    if (response.ok) location.reload();
}

// Загрузка фото
async function uploadPhoto(id) {
    // Создаем временный input для выбора файла
    const tempInput = document.createElement('input');
    tempInput.type = 'file';
    tempInput.accept = 'image/*';
    
    tempInput.onchange = async function() {
        const file = tempInput.files[0];
        if (!file) {
            alert('Выберите файл');
            return;
        }
        
        console.log("Выбран файл:", file.name, file.type, file.size);
        
        if (!file.type.match('image.*')) {
            alert('Можно загружать только изображения (PNG, JPG, JPEG, GIF)');
            return;
        }
        
        const formData = new FormData();
        formData.append('photo', file);
        
        try {
            const response = await fetch(`/super-admin/deputat/${id}/photo`, {
                method: 'POST',
                body: formData
            });
            
            const result = await response.json();
            console.log("Ответ:", result);
            
            if (response.ok) {
                alert('Фото загружено! Страница обновится.');
                location.reload();
            } else {
                alert('Ошибка: ' + (result.error || 'Неизвестная ошибка'));
            }
        } catch (error) {
            console.error('Ошибка:', error);
            alert('Ошибка при загрузке файла');
        }
    };
    
    // Открываем диалог выбора файла
    tempInput.click();
}