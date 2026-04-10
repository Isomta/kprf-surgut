from app import app

print("\n" + "="*50)
print("ЗАРЕГИСТРИРОВАННЫЕ МАРШРУТЫ:")
print("="*50)
for rule in app.url_map.iter_rules():
    print(f"{rule.rule:30} -> {rule.endpoint}")
print("="*50)
