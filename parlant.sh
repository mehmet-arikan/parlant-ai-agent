#!/bin/bash
set -e

echo "🚀 Parlant JSON Q&A Sistemi Kuruluyor..."

# API Key kontrolü fonksiyonu
validate_api_key() {
    local key=$1
    if [[ ${#key} -lt 20 ]]; then
        return 1
    fi
    # Basit format kontrolü (Gemini API key'ler genelde AIza ile başlar)
    if [[ $key == AIza* ]]; then
        return 0
    fi
    return 1
}

# API Key al ve doğrula
get_api_key() {
    while true; do
        echo ""
        echo "🔑 Gemini API anahtarınızı girin:"
        echo "   (https://makersuite.google.com/app/apikey adresinden alabilirsiniz)"
        read -p "API Key: " api_key
        
        if [[ -z "$api_key" ]]; then
            echo "❌ API key boş olamaz!"
            continue
        fi
        
        if validate_api_key "$api_key"; then
            echo "✅ API key formatı geçerli"
            break
        else
            echo "❌ Geçersiz API key formatı. Lütfen tekrar deneyin."
            echo "   (Gemini API key'ler genelde 'AIza' ile başlar ve en az 20 karakter)"
        fi
    done
    
    # API key'i test et
    echo "🔄 API key test ediliyor..."
    if command -v curl >/dev/null 2>&1; then
        test_response=$(curl -s -w "%{http_code}" -o /dev/null \
            -H "Content-Type: application/json" \
            -d '{"contents":[{"parts":[{"text":"test"}]}]}' \
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$api_key")
        
        if [[ "$test_response" == "200" ]]; then
            echo "✅ API key çalışıyor!"
        else
            echo "⚠️  API key test edilemedi (HTTP $test_response). Devam ediliyor..."
        fi
    fi
}

# Önceki kurulumu temizle
cleanup_previous() {
    echo "🧹 Önceki kurulum temizleniyor..."
    sudo systemctl stop parlant 2>/dev/null || true
    sudo systemctl disable parlant 2>/dev/null || true
    sudo rm -rf /opt/parlant
    sudo rm -f /etc/systemd/system/parlant.service
    sudo systemctl daemon-reload
}

# Gerekli paketleri kur
install_dependencies() {
    echo "📦 Gerekli paketler kuruluyor..."
    sudo apt update
    sudo apt install -y python3 python3-pip python3-venv git curl jq
}

# Parlant'ı kur
install_parlant() {
    echo "⚙️  Parlant kuruluyor..."
    sudo mkdir -p /opt/parlant
    cd /opt/parlant
    
    sudo git clone https://github.com/emcie-co/parlant.git .
    sudo chown -R $USER:$USER /opt/parlant
    python3 -m venv venv
    source venv/bin/activate
    venv/bin/pip install --upgrade pip
    venv/bin/pip install "parlant[gemini]"
}

# JSON dosyasını indir
download_json_data() {
    echo "📊 JSON verisi indiriliyor..."
    curl -s "https://dl.dropboxusercontent.com/scl/fi/6fyouegedqg9jl2fkap01/www.alarko-carrier.com.tr.output.20250731-202614.json?rlkey=h1k85rix5hsh1uawqa6loln3c&st=w55o63wv&dl=0" > web_data.json
    
    if [[ ! -s web_data.json ]]; then
        echo "❌ JSON dosyası indirilemedi!"
        exit 1
    fi
    
    echo "✅ JSON dosyası indirildi ($(du -h web_data.json | cut -f1))"
}

# Python handler oluştur
create_python_handler() {
    echo "🐍 Python handler oluşturuluyor..."
    cat > custom_handler.py << 'EOF'
import json
import os
import google.generativeai as genai
from typing import Dict, List, Any

class JSONQAHandler:
    def __init__(self):
        self.json_data = None
        self.model = None
        self.load_json_data()
        self.setup_gemini()
    
    def load_json_data(self):
        """JSON verisini yükle"""
        try:
            with open('/opt/parlant/web_data.json', 'r', encoding='utf-8') as f:
                self.json_data = json.load(f)
            print(f"✅ JSON verisi yüklendi: {len(self.json_data.get('results', []))} kayıt")
        except Exception as e:
            print(f"❌ JSON yükleme hatası: {e}")
            self.json_data = {'results': []}
    
    def setup_gemini(self):
        """Gemini modelini ayarla"""
        try:
            api_key = os.environ.get('GEMINI_API_KEY')
            if not api_key:
                print("❌ GEMINI_API_KEY bulunamadı!")
                return
            
            genai.configure(api_key=api_key)
            self.model = genai.GenerativeModel(
                model_name='gemini-1.5-flash',
                generation_config={
                    'temperature': 0.7,
                    'top_p': 0.8,
                    'max_output_tokens': 2048,
                }
            )
            print("✅ Gemini modeli hazır")
        except Exception as e:
            print(f"❌ Gemini kurulum hatası: {e}")
    
    def extract_performance_data(self) -> Dict[str, Any]:
        """JSON'dan performans verilerini çıkar"""
        if not self.json_data:
            return {}
        
        results = self.json_data.get('results', [])
        
        # İstatistikler
        stats = {
            'total_requests': len(results),
            'successful': len([r for r in results if r.get('status') == 200]),
            'failed': len([r for r in results if r.get('status') != 200]),
            'avg_load_time': 0,
            'total_size_mb': 0
        }
        
        # Yükleme süreleri
        load_times = [r.get('elapsedTime', 0) for r in results if isinstance(r.get('elapsedTime'), (int, float))]
        if load_times:
            stats['avg_load_time'] = sum(load_times) / len(load_times)
            stats['max_load_time'] = max(load_times)
            stats['min_load_time'] = min(load_times)
        
        # Dosya boyutları
        file_sizes = [r.get('size', 0) for r in results if isinstance(r.get('size'), (int, float))]
        if file_sizes:
            stats['total_size_mb'] = sum(file_sizes) / (1024 * 1024)
            stats['max_file_size_mb'] = max(file_sizes) / (1024 * 1024)
        
        # En yavaş dosyalar (>2 saniye)
        slow_files = []
        for r in results:
            elapsed = r.get('elapsedTime', 0)
            if isinstance(elapsed, (int, float)) and elapsed > 2:
                url = r.get('url', '')
                filename = url.split('/')[-1] if url else 'unknown'
                slow_files.append((elapsed, filename, url))
        slow_files = sorted(slow_files, key=lambda x: x[0], reverse=True)[:10]
        
        # En büyük dosyalar (>500KB)
        large_files = []
        for r in results:
            size = r.get('size', 0)
            if isinstance(size, (int, float)) and size > 500000:
                url = r.get('url', '')
                filename = url.split('/')[-1] if url else 'unknown'
                large_files.append((size / (1024 * 1024), filename, url))
        large_files = sorted(large_files, key=lambda x: x[0], reverse=True)[:10]
        
        # Hatalı dosyalar
        error_files = []
        for r in results:
            status = r.get('status')
            if status != 200:
                url = r.get('url', '')
                filename = url.split('/')[-1] if url else 'unknown'
                error_files.append((status, filename, url))
        
        return {
            'stats': stats,
            'slow_files': slow_files,
            'large_files': large_files,
            'error_files': error_files[:20]  # İlk 20 hata
        }
    
    def process_question(self, question: str) -> str:
        """Kullanıcı sorusunu işle"""
        if not self.model:
            return "❌ Gemini modeli kullanılamıyor. API anahtarını kontrol edin."
        
        try:
            # Performans verilerini çıkar
            data = self.extract_performance_data()
            
            if not data:
                return "❌ Performans verileri yüklenemedi."
            
            # Detaylı prompt oluştur
            prompt = self.create_detailed_prompt(question, data)
            
            # Gemini'ye sor
            response = self.model.generate_content(prompt)
            
            if not response.text:
                return "❌ Gemini'den yanıt alınamadı."
            
            return response.text
            
        except Exception as e:
            return f"❌ Analiz hatası: {str(e)}"
    
    def create_detailed_prompt(self, question: str, data: Dict) -> str:
        """Detaylı prompt oluştur"""
        stats = data.get('stats', {})
        
        prompt = f"""
Sen bir web performans uzmanısın. Aşağıdaki veriler www.alarko-carrier.com.tr sitesinin detaylı performans analizi sonuçlarıdır.

📊 GENEL İSTATİSTİKLER:
• Toplam kaynak sayısı: {stats.get('total_requests', 0)}
• Başarılı yüklemeler: {stats.get('successful', 0)}
• Başarısız yüklemeler: {stats.get('failed', 0)}
• Ortalama yükleme süresi: {stats.get('avg_load_time', 0):.2f} saniye
• En yavaş dosya: {stats.get('max_load_time', 0):.2f} saniye
• En hızlı dosya: {stats.get('min_load_time', 0):.2f} saniye
• Toplam veri boyutu: {stats.get('total_size_mb', 0):.1f} MB
• En büyük dosya: {stats.get('max_file_size_mb', 0):.1f} MB

🐌 EN YAVAŞ DOSYALAR (>2 saniye):
"""
        
        # Yavaş dosyalar
        slow_files = data.get('slow_files', [])[:5]
        for elapsed, filename, _ in slow_files:
            prompt += f"• {elapsed:.2f}s - {filename}\n"
        
        prompt += f"\n📦 EN BÜYÜK DOSYALAR (>500KB):\n"
        
        # Büyük dosyalar
        large_files = data.get('large_files', [])[:5]
        for size_mb, filename, _ in large_files:
            prompt += f"• {size_mb:.1f}MB - {filename}\n"
        
        prompt += f"\n❌ HATALAR:\n"
        
        # Hatalar
        error_files = data.get('error_files', [])[:10]
        for status, filename, _ in error_files:
            prompt += f"• HTTP {status} - {filename}\n"
        
        prompt += f"""
🤔 KULLANICI SORUSU: {question}

GÖREV:
1. Bu performans verilerini analiz et
2. Kullanıcının sorusunu bu verilere dayanarak yanıtla
3. Praktik önerilerde bulun
4. Türkçe ve anlaşılır bir dille cevap ver
5. Uygun emojiler kullan
6. Gerekirse teknik detayları açıkla

Cevabın yapıcı, detaylı ve uygulanabilir olsun!
"""
        
        return prompt

# Global handler instance
qa_handler = JSONQAHandler()

def handle_user_message(message: str) -> str:
    """Ana mesaj işleme fonksiyonu"""
    try:
        return qa_handler.process_question(message)
    except Exception as e:
        return f"❌ Sistem hatası: {str(e)}"

# Test fonksiyonu
def test_handler():
    """Handler'ı test et"""
    test_questions = [
        "Web sitesi performansı nasıl?",
        "En yavaş dosyalar neler?",
        "Hangi hatalar var?"
    ]
    
    for q in test_questions:
        print(f"\n🤔 Soru: {q}")
        print(f"🤖 Cevap: {handle_user_message(q)[:100]}...")

if __name__ == "__main__":
    test_handler()
EOF
}

# Systemd servisi oluştur
create_systemd_service() {
    echo "🔧 Systemd servisi oluşturuluyor..."
    sudo tee /etc/systemd/system/parlant.service > /dev/null << EOF
[Unit]
Description=Parlant JSON Q&A System
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/parlant
Environment=PATH=/opt/parlant/venv/bin
EnvironmentFile=/opt/parlant/.env
ExecStart=/opt/parlant/venv/bin/parlant-server run --gemini --host 0.0.0.0 --port 8080
Restart=on-failure
RestartSec=15
TimeoutStartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# Servisi başlat
start_service() {
    echo "🚀 Servis başlatılıyor..."
    sudo systemctl daemon-reload
    sudo systemctl enable parlant
    sudo systemctl start parlant
    
    # Servisin başlamasını bekle
    echo "⏳ Servisin başlaması bekleniyor..."
    for i in {1..30}; do
        if sudo systemctl is-active --quiet parlant; then
            echo "✅ Servis başarıyla başlatıldı!"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    
    echo "❌ Servis başlatılamadı!"
    echo "📋 Servis logları:"
    sudo systemctl status parlant --no-pager
    return 1
}

# Agent ve guideline oluştur
setup_agent() {
    echo "🤖 Agent oluşturuluyor..."
    
    # Parlant CLI'nin hazır olmasını bekle
    for i in {1..10}; do
        if /opt/parlant/venv/bin/parlant --help >/dev/null 2>&1; then
            break
        fi
        echo "⏳ Parlant CLI bekleniyor... ($i/10)"
        sleep 3
    done
    
    # Agent oluştur
    /opt/parlant/venv/bin/parlant agent create \
        --name "Web Performans Uzmanı" \
        --description "Alarko Carrier web sitesi performans verilerini analiz eder. Yükleme sürelerini, dosya boyutlarını, hataları raporlar ve optimizasyon önerileri sunar." || true
    
    echo "✅ Agent oluşturuldu!"
}

# Firewall ayarla
setup_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        echo "🔥 Firewall ayarlanıyor..."
        sudo ufw allow 8080/tcp comment "Parlant Web Interface" 2>/dev/null || true
        echo "✅ Port 8080 açıldı"
    fi
}

# Ana kurulum fonksiyonu
main() {
    echo "🎯 Parlant JSON Q&A Sistemi Kurulum Başlıyor..."
    echo "📅 $(date)"
    echo ""
    
    # API Key al
    get_api_key
    
    # Kurulum adımları
    cleanup_previous
    install_dependencies
    install_parlant
    download_json_data
    create_python_handler
    
    # .env dosyası oluştur
    cat > .env << EOF
GEMINI_API_KEY=$api_key
PYTHONPATH=/opt/parlant
EOF
    
    create_systemd_service
    
    if start_service; then
        setup_agent
        setup_firewall
        
        # Başarı mesajı
        local_ip=$(hostname -I | awk '{print $1}')
        echo ""
        echo "🎉 KURULUM BAŞARIYLA TAMAMLANDI!"
        echo "=================================="
        echo "🌐 Web Arayüzü: http://$local_ip:8080"
        echo "🌐 Localhost:   http://localhost:8080"
        echo ""
        echo "📝 KULLANIM ÖRNEKLERİ:"
        echo "• Web sitesi performansı nasıl?"
        echo "• En yavaş yüklenen dosyalar neler?"
        echo "• Hangi dosyalar en büyük boyutta?"
        echo "• HTTP hataları var mı?"
        echo "• Site optimizasyonu için önerilerin neler?"
        echo ""
        echo "🔧 KONTROL KOMUTLARI:"
        echo "• Durum: sudo systemctl status parlant"
        echo "• Loglar: sudo journalctl -u parlant -f"
        echo "• Yeniden başlat: sudo systemctl restart parlant"
        echo ""
        echo "✨ Sistem hazır! Sorularınızı sorabilirsiniz."
        
    else
        echo "❌ Kurulum başarısız! Logları kontrol edin."
        exit 1
    fi
}

# Script'i çalıştır
main "$@"
