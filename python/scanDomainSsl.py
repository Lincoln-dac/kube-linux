"""
# File       : scanDomainSsl.py
# Time       ：2023/10/24 16:54
# Author     ：Lincoln
# version    ：python 3.8
# Description：
"""
import ssl
import OpenSSL
from datetime import datetime

def check_cert_expiry(domain):
    try:
        cert = ssl.get_server_certificate((domain, 443))
        x509 = OpenSSL.crypto.load_certificate(OpenSSL.crypto.FILETYPE_PEM, cert)
        not_after = x509.get_notAfter().decode('utf-8')
        expiry_date = datetime.strptime(not_after, '%Y%m%d%H%M%SZ')
        days_remaining = (expiry_date - datetime.now()).days
        return days_remaining
    except Exception as e:
        return None

def main():
    domains = ["vpn.fcbox.com"]  # 你可以添加要扫描的域名
    for domain in domains:
        days_remaining = check_cert_expiry(domain)
        if days_remaining is not None:
            print(f"Domain: {domain}, Days until certificate expiration: {days_remaining} days")
        else:
            print(f"Domain: {domain}, Unable to retrieve certificate information")

if __name__ == "__main__":
    main()
