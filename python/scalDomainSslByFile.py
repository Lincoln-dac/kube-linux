"""
# File       : scalDomainSslByFile.py
# Time       ：2023/10/24 17:02
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

def main(filename):
    try:
        with open(filename, 'r') as file:
            domains = file.read().splitlines()
            for domain in domains:
                days_remaining = check_cert_expiry(domain)
                if days_remaining is not None:
                    print(f"Domain: {domain}, Days until certificate expiration: {days_remaining} days")
                else:
                    print(f"Domain: {domain}, Unable to retrieve certificate information")
    except FileNotFoundError:
        print(f"File '{filename}' not found.")
    except Exception as e:
        print(f"An error occurred: {str(e)}")

if __name__ == "__main__":
    filename = "domains.txt"  # 你可以将文件名替换为包含域名列表的文件
    main(filename)
