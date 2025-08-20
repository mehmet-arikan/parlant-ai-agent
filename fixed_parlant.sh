#!/bin/bash

# Systemd servis başlatma
sudo systemctl daemon-reload
sudo systemctl enable parlant
sudo systemctl start parlant && sleep 5 && sudo systemctl is-active --quiet parlant || { echo "Parlant servisi başlatılamadı!"; exit 1; }

# Agent oluşturma - BTU hesaplama özelliği ile geliştirilmiş
sudo -u parlant /opt/parlant/venv/bin/parlant agent create \
  --name "Alarko Carrier Satış Danışmanı" \
  --description "Sen Alarko Carrier'ın uzman satış danışmanısın. Klima, kombi, ısıtma ve soğutma sistemleri konusunda müşterilere yardım ediyorsun. BTU hesaplama konusunda da uzman bilgin var." || { echo "Agent oluşturma başarısız!"; exit 1; }

# BTU hesaplama kuralları ekleme
sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
  --condition "müşteri BTU hesaplama soruyor" \
  --action "BTU hesaplama için şu formülü kullan: Alan (m²) × Yükseklik (m) × 200 = Minimum BTU. Örnek: 20 m² oda için 20 × 2.5 × 200 = 10.000 BTU gerekir. Fazlasıyla 12.000 BTU klima yeterlidir. Güney cephe, üst kat, cam yoğunluğu gibi faktörler %10-20 artış gerektirebilir."

sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
  --condition "müşteri oda büyüklüğü söylüyor" \
  --action "Odanın m² cinsinden alanını öğren ve BTU hesaplama yap. Alan × Yükseklik × 200 formülünü kullan. 15-20 m² için 9.000-12.000 BTU, 20-25 m² için 12.000-18.000 BTU, 25-35 m² için 18.000-24.000 BTU öner."

sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
  --condition "müşteri klima kapasitesi soruyor" \
  --action "Önce odanın m² alanını sor. Tavan yüksekliğini bilip bilmediğini sor - eğer bilmiyorsa 'Genelde evlerde tavan yüksekliği 2,5 metredir, bu değeri kullanarak hesaplayalım' de ve 2,5 metre kabul et. BTU hesaplama: Alan × Yükseklik × 200. Ek faktörler: güney cephe +%15, üst kat +%10, fazla cam +%10. Hesaplamayı açıkla ve sonucu ürünlerimizle eşleştir."

sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
  --condition "müşteri tavan yüksekliği bilmiyor" \
  --action "Müşteriye 'Merak etmeyin, Türkiye'deki evlerin çoğunda standart tavan yüksekliği 2,5 metredir. Bu değerle hesaplama yapabiliriz' diyerek devam et. 2,5 metre kullanarak BTU hesaplamasını tamamla."

# Ürün bilgilerini yükleme - JSON içeriğine göre optimize edilmiş versiyon
cat > /tmp/load_products.py << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import subprocess
import re
import sys

try:
    with open('/tmp/products.json', 'r', encoding='utf-8') as f:
        products = json.load(f)
    
    print(f'📦 Toplam {len(products)} ürün yükleniyor...')
    
    # BTU hesaplama kuralları önce ekleniyor
    btu_rules = [
        ('müşteri BTU hesaplama soruyor veya kaç BTU gerekir diyor', 
         'BTU hesaplama için önce odanın m² alanını sor. Tavan yüksekliğini bilip bilmediğini sor - bilmiyorsa "Merak etmeyin, standart evlerde tavan yüksekliği genelde 2,5 metredir, bu değeri kullanarak hesaplayalım" de. Formül: Alan × Yükseklik × 200 = BTU. Örnek: 20 m² × 2,5 × 200 = 10.000 BTU. Ek faktörler: güney cephe +%15, üst kat +%10, fazla cam +%10. Hesaplamayı açıkla ve uygun ürünleri öner.'),
        
        ('müşteri oda büyüklüğü söylüyor', 
         'BTU hesaplama yap: Alan × 2,5 (standart tavan) × 200. Sonucu söyle ve stokta olan uygun klimaları öner. Güney cephe, üst kat, fazla cam varsa %10-15 fazlası öner.'),
         
        ('müşteri hangi BTU klima almalıyım diyor',
         'Önce odanın kaç m² olduğunu sor. Tavan yüksekliği bilmiyorsa 2,5 metre kabul et. BTU = m² × 2,5 × 200 formülüyle hesapla. Stokta olan uygun klimaları listele.')
    ]
    
    for condition, action in btu_rules:
        result = subprocess.run(
            ['/opt/parlant/venv/bin/parlant', 'guideline', 'create', '--condition', condition, '--action', action],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f'✅ BTU kuralı eklendi: {condition[:50]}...')
    
    # Ürün bilgilerini işle
    successful_products = 0
    
    for product in products:
        name = product.get('Ürün Adı', '')
        if not name:
            continue
            
        category = product.get('Kategori', '')
        normal_price = product.get('Normal Fiyat', '')
        sadakat_price = product.get('Sadakat Fiyatı', '')
        stock = product.get('Stok Durumu', '')
        cooling_capacity = product.get('Soğutma Kapasitesi (BTU/h)', '')
        heating_capacity = product.get('Isıtma Kapasitesi (BTU/h)', '')
        noise_level = product.get('İç Ünite Ses Seviyesi (dB[A])', '')
        link = product.get('Ürün Linki', '')
        
        # BTU değerini çıkar
        btu_match = re.search(r'(\d+\.?\d*)\s*BTU', name, re.IGNORECASE)
        btu = btu_match.group(1).replace('.', '') if btu_match else ''
        
        # Stok durumu kontrolü
        stock_info = '✅ Stokta var' if 'Stokta Var' in stock else '❌ Stokta yok'
        
        # Fiyat bilgisi
        price_info = f'Normal: {normal_price}'
        if sadakat_price and 'Sadakat Fiyatı Yok' not in sadakat_price:
            price_info += f', Sadakat: {sadakat_price}'
            
        # Teknik bilgiler
        tech_info = []
        if cooling_capacity:
            tech_info.append(f'Soğutma: {cooling_capacity} BTU/h')
        if heating_capacity:
            tech_info.append(f'Isıtma: {heating_capacity} BTU/h')
        if noise_level:
            tech_info.append(f'Ses: {noise_level} dB')
            
        tech_details = ', '.join(tech_info) if tech_info else ''
        
        result = None
        
        if category == 'klima' and btu:
            try:
                btu_num = float(btu)
                # BTU aralığına göre oda büyüklüğü
                if btu_num <= 12000:
                    room_size = '15-20 m²'
                elif btu_num <= 18000:
                    room_size = '20-25 m²'
                elif btu_num <= 24000:
                    room_size = '25-35 m²'
                else:
                    room_size = '35+ m²'
                    
                # Koşullar
                conditions = [
                    f'müşteri {btu} BTU klima arıyor',
                    f'müşteri {room_size} oda için klima arıyor', 
                    f'hesaplama sonucu {btu} BTU çıkıyor'
                ]
                
                for condition in conditions:
                    action = f'🏷️ {name} - {stock_info}\\n'
                    action += f'💰 {price_info}\\n'
                    if tech_details:
                        action += f'🔧 {tech_details}\\n'
                    action += f'🏠 {room_size} odalar için ideal\\n'
                    if link:
                        action += f'🔗 Detay: {link}\\n'
                    action += 'İletişim için numaramızı arayın!'
                    
                    result = subprocess.run(
                        ['/opt/parlant/venv/bin/parlant', 'guideline', 'create', '--condition', condition, '--action', action],
                        capture_output=True, text=True
                    )
                    if result.returncode == 0:
                        break
            except ValueError:
                continue
        
        elif category == 'kombi':
            heating_power = product.get('Isıtma Kapasitesi (kW)', '')
            efficiency = product.get('Enerji Verimliliği - Isıtma (%)', '')
            dimensions = product.get('Genişlik/Yükseklik/Derinlik(mm)', '')
            
            condition = f'müşteri kombi arıyor veya {name.split()[1] if len(name.split()) > 1 else "kombi"} model arıyor'
            action = f'🏷️ {name} - {stock_info}\\n'
            action += f'💰 {price_info}\\n'
            if heating_power:
                action += f'🔥 Isıtma Gücü: {heating_power} kW\\n'
            if efficiency:
                action += f'⚡ Verimlilik: %{efficiency}\\n'
            if dimensions:
                action += f'📏 Boyut: {dimensions}\\n'
            if link:
                action += f'🔗 Detay: {link}\\n'
            action += 'Montaj ve servis dahil fiyat için arayın!'
            
            result = subprocess.run(
                ['/opt/parlant/venv/bin/parlant', 'guideline', 'create', '--condition', condition, '--action', action],
                capture_output=True, text=True
            )
        
        elif category == 'multi-klima':
            condition = f'müşteri multi klima veya çoklu klima arıyor'
            action = f'🏷️ {name} - {stock_info}\\n'
            action += f'💰 {price_info}\\n'
            if cooling_capacity:
                action += f'❄️ Kapasiteler: {cooling_capacity} BTU/h\\n'
            if heating_capacity:
                action += f'🔥 Isıtma: {heating_capacity} BTU/h\\n'
            if link:
                action += f'🔗 Detay: {link}\\n'
            action += 'Çoklu oda çözümü için ideal! Detay için arayın.'
            
            result = subprocess.run(
                ['/opt/parlant/venv/bin/parlant', 'guideline', 'create', '--condition', condition, '--action', action],
                capture_output=True, text=True
            )
        
        if result and result.returncode == 0:
            successful_products += 1
        elif result:
            print(f'❌ Hata: {name} - {result.stderr.strip()}')
    
    print(f'\\n✅ {successful_products}/{len(products)} ürün başarıyla yüklendi!')
    print('🧮 BTU hesaplama sistemi aktif!')
    print('💬 Müşteriler artık "Kaç BTU gerekir?" diye sorabilir!')
    
except Exception as e:
    print(f'❌ Kritik hata: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF

# Python scriptini çalıştır
python3 /tmp/load_products.py

# Ek genel kurallar
sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
  --condition "müşteri merhaba diyor veya selamlaşıyor" \
  --action "Merhaba! Ben Alarko Carrier uzman satış danışmanınızım. Klima, kombi, ısıtma-soğutma sistemleri konusunda size yardımcı olabilirim. BTU hesaplama da yapabilirim. Nasıl yardımcı olabilirim?"

sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
  --condition "müşteri fiyat soruyor" \
  --action "Güncel fiyatlarımızı paylaştım. Stokta olan ürünlerde hem normal hem sadakat fiyatlarımız mevcut. Montaj, servis ve garanti detayları için iletişime geçin. Hangi ürün sizi ilgilendiriyor?"

sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
  --condition "müşteri montaj veya kurulum soruyor" \
  --action "Tüm ürünlerimizde profesyonel montaj hizmeti sunuyoruz. Montaj ücreti ürüne ve bölgeye göre değişiklik gösterir. Tam fiyat teklifi için bayimizle iletişime geçin. Garanti kapsamında servis de sağlıyoruz."

# Temizlik
rm -f /tmp/load_products.py

echo "✅ Tüm kurallar başarıyla eklendi!"
echo "🔄 Servisi yeniden başlatıyor..."
sudo systemctl restart parlant

# Final kontrol
sleep 5
if sudo systemctl is-active --quiet parlant; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo "🎉 Sistem hazır! Test et: http://$SERVER_IP:8800/chat/"
else
    echo "❌ Servis sorunu! Logları kontrol edin:"
    sudo journalctl -u parlant -n 10 --no-pager
fi
