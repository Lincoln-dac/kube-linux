import socket
import subprocess
import os
def get_github_ip():
    try:
        github_ip = socket.gethostbyname('github.com')
        return github_ip
    except socket.error as e:
        print("Error:", e)
        return None

def add_ip_to_hosts_file(ip_address, domain):
    try:
        with open(r'C:\Windows\System32\drivers\etc\hosts', 'a') as hosts_file:
            hosts_file.write(ip_address + ' ' + domain + '\n')
        print("IP address added to hosts file.")
    except Exception as e:
        print("Error:", e)

def flush_dns_cache():
    try:
        os.system('ipconfig /flushdns')
        print("DNS cache flushed successfully.")
    except Exception as e:
        print("Error flushing DNS cache:", e)

github_ip_address = get_github_ip()
if github_ip_address:
    add_ip_to_hosts_file(github_ip_address, 'github.com')
    flush_dns_cache()
