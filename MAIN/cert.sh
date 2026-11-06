sudo apt update
sudo apt install -y ca-certificates

sudo install -m 0644 /home/admin/ca.crt /usr/local/share/ca-certificates/local-network-ca.crt
sudo update-ca-certificates
sudo apt install -y libnss3-tools
mkdir -p ~/.pki/nssdb

if [ ! -f ~/.pki/nssdb/cert9.db ]; then
    certutil -N -d sql:$HOME/.pki/nssdb --empty-password
fi

certutil -A -d sql:$HOME/.pki/nssdb -n "Local Network CA" -t "C,," -i /home/admin/ca.crt