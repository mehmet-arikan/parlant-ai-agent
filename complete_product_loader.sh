#!/bin/bash

echo "📦 PARLANT ÜRÜN VERİLERİ YÜKLEYİCİ"
echo "================================="

# Servisisin çalıştığını kontrol et
if ! sudo systemctl is-active --quiet parlant; then
    echo "❌ Parlant servisi çalışmıyor!"
    echo "🚀 Servisi başlatıyor..."
    sudo systemctl start parlant
    sleep 5
fi

# JSON dosyasını indir
echo "📥 Ürün verileri indiriliyor..."
if ! curl -s --max-time 30 --fail \
    "https://dl.dropboxusercontent.com/scl/fi/vn81hzkmadmmdl4jo9lpj/products.json?rlkey=xyx7qo17ntjiswa9ed7bia8xw&st=m0dqfy9r&dl=0" \
    > /tmp/products.json; then
    echo "❌ Ürün verileri indirilemedi!"
    echo "🔄 Alternatif yöntem deneniyor..."
    
    # Alternatif URL dene
    if ! wget -q -O /tmp/products.json \
        "https://dl.dropboxusercontent.com/scl/fi/vn81hzkmadmmdl4jo9lpj/products.json?rlkey=xyx7qo17ntjiswa9ed7bia8xw&st=m0dqfy9r&dl=0"; then
        echo "❌ İndirme başarısız! İnternet bağlantısını kontrol edin."
        exit 1
    fi
fi

# Dosya kontrolü
if [ ! -f /tmp/products.json ]; then
    echo "❌ JSON dosyası bulunamadı!"
    exit 1
fi

echo "📊 Dosya boyutu: $(du -h /tmp/products.json | cut -f1)"

# JSON doğrulama
if ! jq . /tmp/products.json >/dev/null 2>&1; then
    echo "❌ Geçersiz JSON formatı!"
    echo "📋 Dosya içeriği:"
    head -n 5 /tmp/products.json
    exit 1
fi

PRODUCT_COUNT=$(jq length /tmp/products.json)
echo "✅ JSON geçerli! $PRODUCT_COUNT ürün bulundu."

# Python script ile ürün kurallarını oluştur
echo "🔄 Ürün kuralları oluşturuluyor..."

cat > /tmp/create_all_product_rules.py << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import subprocess
import re
import sys
import time

def safe_guideline_create(condition, action, max_retries=3):
    """Güvenli guideline ekleme fonksiyonu"""
    for attempt in range(max_retries):
        try:
            # Özel karakterleri escape et
            safe_condition = condition.replace('"', '\\"').replace("'", "\\'")
            safe_action = action.replace('"', '\\"').replace("'", "\\'")
            
            result = subprocess.run(
                ['/opt/parlant/venv/bin/parlant', 'guideline', 'create', 
                 '--condition', safe_condition, '--action', safe_action],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                return True
            else:
                print(f"  Deneme {attempt + 1}: {result.stderr.strip()[:100]}")
                time.sleep(1)
                
        except subprocess.TimeoutExpired:
            print(f"  Timeout deneme {attempt + 1}")
            time.sleep(1)
        except Exception as e:
            print(f"  Hata deneme {attempt + 1}: {str(e)[:100]}")
            time.sleep(1)
    
    return False

try:
    with open('/tmp/products.json', 'r', encoding='utf-8') as f:
        products = json.load(f)
    
    print(f'📦 {len(products)} ürün işleniyor...')
    
    # Ürünleri kategorilere ayır
    klima_products = []
    kombi_products = []
    multi_klima_products = []
    other_products = []
    
    for product in products:
        category = product.get('Kategori', '').lower()
        if 'klima' in category and 'multi' not in category:
            klima_products.append(product)
        elif 'kombi' in category:
            kombi_products.append(product)
        elif 'multi' in category:
            multi_klima_products.append(product)
        else:
            other_products.append(product)
    
    print(f'🌬️ Klima: {len(klima_products)} ürün')
    print(f'🔥 Kombi: {len(kombi_products)} ürün')
    print(f'🏢 Multi-klima: {len(multi_klima_products)} ürün')
    print(f'🔧 Diğer: {len(other_products)} ürün')
    
    successful_rules = 0
    
    # BTU kategorilerine göre klima kuralları
    btu_categories = {
        '9000': {'products': [], 'room': '12-18 m²'},
        '12000': {'products': [], 'room': '18-25 m²'},
        '18000': {'products': [], 'room': '25-35 m²'},
        '24000': {'products': [], 'room': '35-45 m²'}
    }
    
    # Klimaları BTU'ya göre kategorize et
    for product in klima_products:
        name = product.get('Ürün Adı', '')
        btu_match = re.search(r'(\d+\.?\d*)\s*BTU', name, re.IGNORECASE)
        if btu_match:
            btu = int(float(btu_match.group(1).replace('.', '')))
            
            if btu <= 9000:
                btu_categories['9000']['products'].append(product)
            elif btu <= 12000:
                btu_categories['12000']['products'].append(product)
            elif btu <= 18000:
                btu_categories['18000']['products'].append(product)
            elif btu <= 24000:
                btu_categories['24000']['products'].append(product)
    
    # Her BTU kategorisi için kurallar oluştur
    for btu_level, data in btu_categories.items():
        products_list = data['products']
        room_size = data['room']
        
        if not products_list:
            continue
            
        print(f'🌬️ {btu_level} BTU klima kuralları oluşturuluyor...')
        
        # İlk 3 ürünü al
        top_products = products_list[:3]
        
        # Kural metni oluştur
        rule_text = f'🌬️ {btu_level} BTU Klima Modelleri ({room_size}):\\n\\n'
        
        for i, product in enumerate(top_products, 1):
            name = product.get('Ürün Adı', '')
            normal_price = product.get('Normal Fiyat', '')
            sadakat_price = product.get('Sadakat Fiyatı', '')
            stock = product.get('Stok Durumu', '')
            cooling = product.get('Soğutma Kapasitesi (BTU/h)', '')
            heating = product.get('Isıtma Kapasitesi (BTU/h)', '')
            link = product.get('Ürün Linki', '')
            
            stock_emoji = '✅' if 'Stokta Var' in stock else '❌'
            
            rule_text += f'{i}. 🏷️ {name}\\n'
            rule_text += f'   {stock_emoji} {stock}\\n'
            rule_text += f'   💰 Normal: {normal_price}'
            
            if sadakat_price and 'Yok' not in sadakat_price:
                rule_text += f' | Sadakat: {sadakat_price}'
            rule_text += '\\n'
            
            if cooling:
                rule_text += f'   ❄️ Soğutma: {cooling}\\n'
            if heating:
                rule_text += f'   🔥 Isıtma: {heating}\\n'
            if link:
                rule_text += f'   🔗 {link}\\n'
            rule_text += '\\n'
        
        rule_text += '📞 Montaj dahil fiyat için iletişime geçin!'
        
        # Farklı koşullar için kuralı ekle
        conditions = [
            f'müşteri {btu_level} BTU klima arıyor',
            f'müşteri {btu_level} BTU klima',
            f'{btu_level} BTU klima var mı',
            f'müşteri {room_size} oda için klima arıyor'
        ]
        
        for condition in conditions:
            if safe_guideline_create(condition, rule_text):
                successful_rules += 1
                break
    
    # Kombi kuralları oluştur
    if kombi_products:
        print('🔥 Kombi kuralları oluşturuluyor...')
        
        kombi_rule = '🔥 Alarko Carrier Kombi Modelleri:\\n\\n'
        
        for i, kombi in enumerate(kombi_products[:5], 1):
            name = kombi.get('Ürün Adı', '')
            normal_price = kombi.get('Normal Fiyat', '')
            sadakat_price = kombi.get('Sadakat Fiyatı', '')
            stock = kombi.get('Stok Durumu', '')
            heating_power = kombi.get('Isıtma Kapasitesi (kW)', '')
            efficiency = kombi.get('Enerji Verimliliği - Isıtma (%)', '')
            link = kombi.get('Ürün Linki', '')
            
            stock_emoji = '✅' if 'Stokta Var' in stock else '❌'
            
            kombi_rule += f'{i}. 🏷️ {name}\\n'
            kombi_rule += f'   {stock_emoji} {stock}\\n'
            kombi_rule += f'   💰 Normal: {normal_price}'
            
            if sadakat_price and 'Yok' not in sadakat_price:
                kombi_rule += f' | Sadakat: {sadakat_price}'
            kombi_rule += '\\n'
            
            if heating_power:
                kombi_rule += f'   🔥 Güç: {heating_power} kW\\n'
            if efficiency:
                kombi_rule += f'   ⚡ Verimlilik: %{efficiency}\\n'
            if link:
                kombi_rule += f'   🔗 {link}\\n'
            kombi_rule += '\\n'
        
        kombi_rule += '📞 Montaj ve servis dahil fiyat için arayın!'
        
        kombi_conditions = [
            'müşteri kombi modelleri soruyor',
            'müşteri kombi arıyor',
            'hangi kombiler var',
            'kombi listesi'
        ]
        
        for condition in kombi_conditions:
            if safe_guideline_create(condition, kombi_rule):
                successful_rules += 1
                break
    
    # Genel katalog kuralı
    catalog_rule = f'📋 Alarko Carrier Ürün Kataloğu:\\n\\n'
    catalog_rule += f'🌬️ KLİMA MODELLERİ:\\n'
    
    for btu_level, data in btu_categories.items():
        if data['products']:
            catalog_rule += f'• {btu_level} BTU: {len(data["products"])} model ({data["room"]})\\n'
    
    catalog_rule += f'\\n🔥 KOMBİ MODELLERİ:\\n'
    catalog_rule += f'• {len(kombi_products)} farklı model\\n'
    
    if multi_klima_products:
        catalog_rule += f'\\n🏢 MULTİ KLİMA:\\n'
        catalog_rule += f'• {len(multi_klima_products)} sistem\\n'
    
    catalog_rule += '\\n📞 Hangi ürünle ilgileniyorsunuz? Size uygun modeli önerebilirim!'
    
    catalog_conditions = [
        'müşteri ürün listesi istiyor',
        'müşteri katalog istiyor',
        'hangi ürünler var',
        'klima modelleri neler'
    ]
    
    for condition in catalog_conditions:
        if safe_guideline_create(condition, catalog_rule):
            successful_rules += 1
            break
    
    print(f'\\n✅ Toplam {successful_rules} ürün kuralı eklendi!')
    print(f'🌬️ {sum(len(data["products"]) for data in btu_categories.values())} klima işlendi')
    print(f'🔥 {len(kombi_products)} kombi işlendi')
    
except Exception as e:
    print(f'❌ Kritik hata: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF

# Python scriptini çalıştır
if python3 /tmp/create_all_product_rules.py; then
    echo "✅ Ürün kuralları başarıyla eklendi!"
else
    echo "❌ Ürün kuralları eklenirken hata oluştu!"
    exit 1
fi

# Temizlik
rm -f /tmp/create_all_product_rules.py /tmp/products.json

# Kural sayısını kontrol et
GUIDELINE_COUNT=$(sudo -u parlant /opt/parlant/venv/bin/parlant guideline list 2>/dev/null | wc -l)
echo "📊 Toplam kural sayısı: $GUIDELINE_COUNT"

# Servisi yeniden başlat
echo "🔄 Servisi yeniden başlatıyor..."
sudo systemctl restart parlant
sleep 5

if sudo systemctl is-active --quiet parlant; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "🎉 ÜRÜN VERİLERİ YÜKLEME TAMAMLANDI!"
    echo "===================================="
    echo ""
    echo "🌐 Test et: http://$SERVER_IP:8800/chat/"
    echo ""
    echo "💬 Test soruları:"
    echo "   • Klima modelleri neler?"
    echo "   • 12000 BTU klima var mı?"
    echo "   • Kombi arıyorum"
    echo "   • 20 metrekare için kaç BTU gerekir?"
    echo "   • Ürün listesi"
else
    echo "❌ Servis başlatılamadı! Logları kontrol edin:"
    sudo journalctl -u parlant -n 10 --no-pager
fi
