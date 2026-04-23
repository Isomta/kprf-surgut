import sqlite3
import psycopg2
from psycopg2.extensions import AsIs

# ⚙️ Настройки (пароль подставьте свой, если меняли)
SQLITE_DB = 'instance/deputat.db'
PG_DSN = 'postgresql://kprf_db:SimplePass123@127.0.0.1:5432/kprf_surgut'

# 📋 Порядок создания таблиц (с учётом FK)
TABLE_ORDER = ['topics', 'deputats', 'address_boundaries', 'campaign_points', 'appeals']

# 🗺 Маппинг типов SQLite -> PostgreSQL
TYPE_MAP = {
    'INTEGER': 'INTEGER', 'TEXT': 'TEXT', 'REAL': 'REAL',
    'DATETIME': 'TIMESTAMP', 'BOOLEAN': 'BOOLEAN'
}

def get_sqlite_cols(table):
    cur.execute(f"PRAGMA table_info({table})")
    return cur.fetchall()

try:
    conn_sqlite = sqlite3.connect(SQLITE_DB)
    conn_pg = psycopg2.connect(PG_DSN)
    cur = conn_sqlite.cursor()
    cur_pg = conn_pg.cursor()

    print("🔍 Создаём таблицы в PostgreSQL...")
    for table in TABLE_ORDER:
        cols = get_sqlite_cols(table)
        col_defs = []
        pk_cols = []
        for _, name, col_type, notnull, dflt, pk in cols:
            # Определяем PG-тип
            base = col_type.split('(')[0].upper()
            pg_type = TYPE_MAP.get(base, base)
            if 'VARCHAR' in col_type.upper():
                length = col_type.split('(')[1].split(')')[0]
                pg_type = f"VARCHAR({length})"
            
            # INTEGER PRIMARY KEY -> SERIAL в PG
            if pk:
                col_defs.append(f'"{name}" SERIAL')
                pk_cols.append(name)
            else:
                col_defs.append(f'"{name}" {pg_type}')
                
        if pk_cols:
            col_defs.append(f"PRIMARY KEY ({', '.join(pk_cols)})")
            
        create_sql = f"CREATE TABLE IF NOT EXISTS {table} ({', '.join(col_defs)})"
        cur_pg.execute(create_sql)
        conn_pg.commit()
    print("✅ Таблицы созданы.")

    print("📦 Переносим данные...")
    for table in TABLE_ORDER:
        cur.execute(f"SELECT * FROM {table}")
        rows = cur.fetchall()
        if not rows:
            continue
        col_names = [desc[0] for desc in cur.description]
        placeholders = ', '.join(['%s'] * len(col_names))
        cols_str = ', '.join([f'"{c}"' for c in col_names])
        insert_sql = f"INSERT INTO {table} ({cols_str}) VALUES ({placeholders})"
        
        # PG строго относится к типам, приводим 0/1 к bool для BOOLEAN-полей
        clean_rows = []
        for row in rows:
            clean_rows.append(tuple(None if v == '' else v for v in row))
            
        cur_pg.executemany(insert_sql, clean_rows)
        conn_pg.commit()
        print(f"  ➡️ {table}: {len(rows)} записей")
        
        # Сброс счётчика SERIAL
        cur_pg.execute(f"""
            SELECT column_name FROM information_schema.columns 
            WHERE table_name='{table}' AND column_default LIKE 'nextval%'
        """)
        seq_col = cur_pg.fetchone()
        if seq_col:
            cur_pg.execute(f"SELECT setval(pg_get_serial_sequence('{table}', '{seq_col[0]}'), COALESCE((SELECT MAX({seq_col[0]}) FROM {table}), 1), false)")
            conn_pg.commit()
            
    print("🎉 Миграция завершена успешно!")

except Exception as e:
    print(f"❌ Ошибка: {e}")
    conn_pg.rollback()
finally:
    if conn_sqlite: conn_sqlite.close()
    if conn_pg: conn_pg.close()
