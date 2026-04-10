// Глобальные переменные
let currentDeputat = null;
let lastAddress = null;

// Загрузка списка улиц для datalist
async function loadStreets() {
    const response = await fetch('/api/streets');
    const streets = await response.json();
    const streetList = document.getElementById('streetList');
    const modalStreetList = document.getElementById('modalStreetList');
    streetList.innerHTML = '';
    modalStreetList.innerHTML = '';
    streets.forEach(s => {
        const option = document.createElement('option');
        option.value = s;
        streetList.appendChild(option);
        const option2 = document.createElement('option');
        option2.value = s;
        modalStreetList.appendChild(option2);
    });
}

// Загрузка домов для выбранной улицы
async function loadHouses(street, targetListId) {
    if (!street) {
        document.getElementById(targetListId).innerHTML = '';
        return;
    }
    const response = await fetch(`/api/houses/${encodeURIComponent(street)}`);
    const houses = await response.json();
    const list = document.getElementById(targetListId);
    list.innerHTML = '';
    houses.forEach(h => {
        const option = document.createElement('option');
        option.value = h;
        list.appendChild(option);
    });
}

// Поиск депутата
async function searchDeputat() {
    const street = document.getElementById('street').value.trim();
    const house = document.getElementById('house').value.trim();
    const errorDiv = document.getElementById('searchError');
    if (!street || !house) {
        errorDiv.innerText = 'Введите улицу и номер дома';
        return;
    }
    try {
        const response = await fetch('/api/deputat_by_address', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({street, house})
        });
        if (!response.ok) {
            const error = await response.json();
            errorDiv.innerText = error.error;
            document.getElementById('deputatInfo').style.display = 'none';
            return;
        }
        const data = await response.json();
        currentDeputat = data.deputat;
        document.getElementById('deputatName').innerText = data.deputat.fio;
        document.getElementById('uchastok').innerText = data.deputat.uchastok;
        document.getElementById('birthDate').innerText = data.deputat.birth_date;
        document.getElementById('education').innerText = data.deputat.education;
        document.getElementById('experience').innerText = data.deputat.experience;
        document.getElementById('address').innerText = data.deputat.reception_address;
        document.getElementById('phone').innerText = data.deputat.phone;
        document.getElementById('email').innerText = data.deputat.email;
        // Инициализация карты с адресом приемной
        if (data.deputat.reception_address) {
            initMap(data.deputat.reception_address);
        }
        document.getElementById('totalAppeals').innerText = data.stats.total;
        document.getElementById('newAppeals').innerText = data.stats.new;
        document.getElementById('inWorkAppeals').innerText = data.stats.in_work;
        document.getElementById('completedAppeals').innerText = data.stats.completed;
        document.getElementById('rejectedAppeals').innerText = data.stats.rejected;
        const topicsDiv = document.getElementById('topicsStats');
        topicsDiv.innerHTML = '';
        for (const [topic, count] of Object.entries(data.topics_stats)) {
            topicsDiv.innerHTML += `<div class="topic-tag">${topic}: ${count}</div>`;
        }
        document.getElementById('deputatInfo').style.display = 'block';
        errorDiv.innerText = '';
        lastAddress = {street, house};
    } catch (error) {
        errorDiv.innerText = 'Ошибка при загрузке данных';
    }
}

// Загрузка тем для выпадающего списка
async function loadTopics() {
    const response = await fetch('/api/topics');
    const topics = await response.json();
    const select = document.getElementById('topic');
    select.innerHTML = '<option value="">Выберите тему</option>';
    topics.forEach(topic => {
        select.innerHTML += `<option value="${topic}">${topic}</option>`;
    });
}

// Открыть модальное окно обращения
function openAppealForm() {
    if (!currentDeputat) {
        alert('Сначала найдите депутата по вашему адресу');
        return;
    }
    document.getElementById('appealModal').style.display = 'flex';
    if (lastAddress) {
        document.getElementById('modalStreet').value = lastAddress.street;
        document.getElementById('modalHouse').value = lastAddress.house;
        loadHouses(lastAddress.street, 'modalHouseList');
    }
}

function closeModal() {
    document.getElementById('appealModal').style.display = 'none';
    document.getElementById('appealForm').reset();
}

// Отправка обращения
document.getElementById('appealForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const street = document.getElementById('modalStreet').value.trim();
    const house = document.getElementById('modalHouse').value.trim();
    const topic = document.getElementById('topic').value;
    const text = document.getElementById('text').value.trim();
    const fio = document.getElementById('fio').value.trim();
    const phone = document.getElementById('phoneInput').value.trim();
    const email = document.getElementById('emailInput').value.trim();
    const needVisit = document.getElementById('needVisit').checked;
    const consent = document.getElementById('consent').checked;
    if (!consent) {
        alert('Необходимо согласие на обработку персональных данных');
        return;
    }
    if (!street || !house || !topic || !text) {
        alert('Заполните обязательные поля: адрес, тему и текст обращения');
        return;
    }
    try {
        const response = await fetch('/api/create_appeal', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({street, house, topic, text, fio, phone, email, need_visit: needVisit})
        });
        if (response.ok) {
            alert('Обращение успешно отправлено!');
            closeModal();
            if (street === lastAddress?.street && house === lastAddress?.house) {
                searchDeputat();
            }
        } else {
            const error = await response.json();
            alert('Ошибка: ' + error.error);
        }
    } catch (error) {
        alert('Ошибка при отправке обращения');
    }
});

// Инициализация после загрузки DOM
document.addEventListener('DOMContentLoaded', () => {
    loadStreets();
    loadTopics();
    // Подключаем обработчики для автодополнения домов
    document.getElementById('street').addEventListener('input', (e) => {
        loadHouses(e.target.value, 'houseList');
    });
    document.getElementById('modalStreet').addEventListener('input', (e) => {
        loadHouses(e.target.value, 'modalHouseList');
    });
});

// Установка текущего года в подвале
document.addEventListener('DOMContentLoaded', function() {
    const yearSpan = document.querySelector('footer p');
    if (yearSpan) {
        const currentYear = new Date().getFullYear();
        yearSpan.innerHTML = yearSpan.innerHTML.replace('{% raw %}{{ now.year }}{% endraw %}', currentYear);
    }
});

// Глобальная переменная для карты
let map = null;

// Инициализация карты
function initMap(address) {
    const mapContainer = document.getElementById('map');
    if (!mapContainer) return;
    
    // Показываем контейнер карты
    mapContainer.style.display = 'block';
    
    // Если карта уже создана, удаляем её
    if (map) {
        map.remove();
    }
    
    // Геокодирование адреса (преобразование в координаты)
    fetch(`https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(address)}&limit=1`)
        .then(response => response.json())
        .then(data => {
            if (data && data.length > 0) {
                const lat = data[0].lat;
                const lon = data[0].lon;
                
                map = L.map('map').setView([lat, lon], 15);
                L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                }).addTo(map);
                
                L.marker([lat, lon]).addTo(map)
                    .bindPopup(`<b>Приемная депутата</b><br>${address}`)
                    .openPopup();
            } else {
                mapContainer.style.display = 'none';
                console.log('Адрес не найден на карте');
            }
        })
        .catch(error => {
            console.error('Ошибка геокодирования:', error);
            mapContainer.style.display = 'none';
        });
}

// Установка текущего года
document.addEventListener('DOMContentLoaded', function() {
    const yearSpan = document.getElementById('currentYear');
    if (yearSpan) {
        yearSpan.textContent = new Date().getFullYear();
    }
});