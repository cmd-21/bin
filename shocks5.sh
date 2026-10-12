Untuk menyembunyikan file-file proxy agar tidak berada di folder /root dan lebih menyatu dengan sistem, kita bisa menaruhnya di dalam folder tersembunyi di direktori /opt (direktori standar Linux untuk software tambahan).

Dalam skrip modifikasi ini, sistem akan otomatis membuat folder tersembunyi di /opt/.sys_proxy/ dan meletakkan seluruh file core Python serta watchdog-nya di sana.

Silakan copy-paste perintah berikut di terminal Anda untuk membuat installer.sh yang baru:

Bash
cat << 'INSTALLEREOF' > installer.sh
#!/bin/bash

clear
echo "=================================================="
echo " SOCKS5 PROXY AUTO-INSTALLER (HIDDEN SYSTEM)      "
echo " Fitur: Fast-Connect, Anti-Crash, Auto-Reconnect  "
echo "=================================================="
echo ""

# 1. Input Konfigurasi
read -p "Masukkan Port Proxy [Default: 1080]: " PORT
PORT=${PORT:-1080}

read -p "Gunakan Username & Password? (y/n) [Default: y]: " USE_AUTH
USE_AUTH=${USE_AUTH:-y}

if [[ "$USE_AUTH" =~ ^[Yy]$ ]]; then
    AUTH_BOOL="True"
    read -p "Masukkan Username: " USERNAME
    read -p "Masukkan Password: " PASSWORD
    echo "[+] Mode Autentikasi: AKTIF"
else
    AUTH_BOOL="False"
    USERNAME=""
    PASSWORD=""
    echo "[-] Mode Autentikasi: TANPA PASSWORD (Terbuka Publik)"
fi

# Buat direktori tersembunyi di dalam sistem
SYS_DIR="/opt/.sys_proxy"
mkdir -p $SYS_DIR

# 2. Membuat Skrip Core Python (socks5)
echo "[*] Membangun core proxy SOCKS5 di $SYS_DIR..."
cat << PYEOF > $SYS_DIR/proxy_socks5.py
import socket, threading, select, struct, sys

HOST = '0.0.0.0'
PORT = $PORT
AUTH = $AUTH_BOOL
USERNAME = '$USERNAME'
PASSWORD = '$PASSWORD'

class SocksProxy(threading.Thread):
    def __init__(self, connection):
        super().__init__()
        self.connection = connection

    def run(self):
        try:
            client_greeting = self.connection.recv(262)
            if not client_greeting: return

            if AUTH:
                self.connection.sendall(struct.pack("!BB", 5, 2))
                auth_version = self.connection.recv(1)[0]
                ulen = self.connection.recv(1)[0]
                uname = self.connection.recv(ulen).decode()
                plen = self.connection.recv(1)[0]
                upass = self.connection.recv(plen).decode()
                
                if uname == USERNAME and upass == PASSWORD:
                    self.connection.sendall(struct.pack("!BB", 1, 0))
                else:
                    self.connection.sendall(struct.pack("!BB", 1, 1))
                    return
            else:
                self.connection.sendall(struct.pack("!BB", 5, 0))

            req = self.connection.recv(4)
            if len(req) < 4: return
            version, cmd, _, address_type = struct.unpack("!BBBB", req)
            
            if address_type == 1:
                address = socket.inet_ntoa(self.connection.recv(4))
            elif address_type == 3:
                domain_length = self.connection.recv(1)[0]
                address = self.connection.recv(domain_length).decode()
            else:
                return
            
            port = struct.unpack('!H', self.connection.recv(2))[0]

            if cmd == 1:
                remote = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                remote.connect((address, port))
                self.connection.sendall(struct.pack("!BBBBIH", 5, 0, 0, 1, 0, 0))
                self.exchange_loop(self.connection, remote)
        except Exception:
            pass
        finally:
            self.connection.close()

    def exchange_loop(self, client, remote):
        while True:
            r, _, _ = select.select([client, remote], [], [])
            if client in r:
                data = client.recv(8192)
                if not data: break
                remote.sendall(data)
            if remote in r:
                data = remote.recv(8192)
                if not data: break
                client.sendall(data)

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind((HOST, PORT))
server.listen(500)
while True:
    try:
        conn, addr = server.accept()
        SocksProxy(conn).start()
    except Exception:
        pass
PYEOF

# 3. Membuat Skrip Watchdog (Penjaga Proses & Anti-Double)
echo "[*] Mengonfigurasi sistem Watchdog anti-mati..."
cat << 'WATCHDOGEOF' > /opt/.sys_proxy/proxy_watchdog.sh
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

if ! ps aux | grep "[p]roxy_socks5.py" > /dev/null; then
    PORT=$(grep "^PORT =" /opt/.sys_proxy/proxy_socks5.py | tr -dc '0-9')
    if [ -n "$PORT" ]; then
        fuser -k -n tcp $PORT >/dev/null 2>&1
        sleep 1
    fi
    nohup /usr/bin/python3 /opt/.sys_proxy/proxy_socks5.py > /dev/null 2>&1 &
fi
WATCHDOGEOF
chmod +x /opt/.sys_proxy/proxy_watchdog.sh

# 4. Mendaftarkan ke Cronjob
echo "[*] Memasang jadwal auto-reconnect di Crontab..."
(crontab -l 2>/dev/null | grep -v "proxy_watchdog.sh"; echo "* * * * * /opt/.sys_proxy/proxy_watchdog.sh"; echo "@reboot /opt/.sys_proxy/proxy_watchdog.sh") | crontab -

# 5. Konfigurasi Firewall
echo "[*] Mengonfigurasi Firewall..."
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
service iptables save >/dev/null 2>&1

if [ -f /etc/csf/csf.conf ]; then
    sed -i "s/TCP_IN = \"/TCP_IN = \"$PORT,/g" /etc/csf/csf.conf
    csf -r >/dev/null 2>&1
fi

# 6. Memulai Eksekusi Awal
echo "[*] Menjalankan Proxy Server..."
fuser -k -n tcp $PORT >/dev/null 2>&1
/opt/.sys_proxy/proxy_watchdog.sh
sleep 2

echo ""
echo "=================================================="
echo "          INSTALASI PROXY BERHASIL                "
echo "=================================================="
echo "IP Server : 38.121.115.30"
echo "Port      : $PORT"
if [[ "$AUTH_BOOL" == "True" ]]; then
    echo "Username  : $USERNAME"
    echo "Password  : $PASSWORD"
else
    echo "Autentikasi: TANPA PASSWORD"
fi
echo "Lokasi    : Tersembunyi di $SYS_DIR"
echo "Status    : AKTIF (Terkunci permanen di sistem)"
echo "=================================================="
