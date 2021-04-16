#!/usr/bin/python3
# -*- coding: utf-8 -*-

from datetime import date, timedelta
from email.header import Header
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr
from os.path import basename
import gitlab
import smtplib


def main():
    start_time = (date.today() + timedelta(days=-1)).strftime("%Y-%m-%d %H:%M:%S")
    end_time = date.today().strftime("%Y-%m-%d %H:%M:%S")
    admin_address = 'xxxx.xxx.com, xxxx.xxx.com'
    data = get_data(start_time, end_time)
    save_to_file(data)
    email_admin(admin_address, data)


def get_data(start_time, end_time):
    stats = {}

    url_gitlab = 'http://00.00.0.0/'
    private_token = 'xxxxxx'
    gl = gitlab.Gitlab(url_gitlab, private_token=private_token, api_version='4')
    projects = gl.projects.list(all=True)

    for project in projects:
        branches = project.branches.list()
        for branch in branches:
            commits = project.commits.list(all=True,
                                           query_parameters={'since': start_time, 'until': end_time, 'ref_name': branch.name})
            for commit in commits:
                com = project.commits.get(commit.id)
                user_name = str(com.committer_name)
                if user_name in stats.keys():
                    stats[user_name]['additions'] = stats[user_name]['additions'] + com.stats['additions']
                    stats[user_name]['deletions'] = stats[user_name]['deletions'] + com.stats['deletions']
                    stats[user_name]['total'] = stats[user_name]['total'] + com.stats['total']
                else:
                    stats[user_name] = com.stats
    return stats


def save_to_file(data):
    with open('key.prom', 'w') as file:
        for key in data.keys():
            file.write('fc_user_id{id="' + key + '"} ' + str(data[key]['additions']) + '\n')


def email_admin(admin_address, data):
    email_content = '''<table border="1" style="border-collapse:collapse;border: 1px solid #aaa;">
    <tr style="font-weight:bold; text-align:center; background-color: #eeeeee">
    <td style="width:150px">序号</td><td style="width:150px">姓名</td><td style="width:150px">新增代码行数</td>
    <td style="width:150px">删除代码行数</td><td style="width:150px">合计修改行数</td></tr>'''
    serial = 1
    for key in data.keys():
        email_content += '<tr style="text-align:center; ">'
        email_content += '<td>' + str(serial) + '</td><td>' + str(key) + '</td><td>' + str(data[key]['additions']) + '</td><td>' + \
                         str(data[key]['deletions']) + '</td><td>' + str(data[key]['total']) + '</td></tr>'
        serial += 1
    email_content += '</table>'
    email_subject = '【' + (date.today() + timedelta(days=-1)).strftime("%Y-%m-%d") + '】代码提交量统计'
    email_content = '<b>' + email_subject + '</b> <br/><br/>' + email_content
    send_email(admin_address, email_subject, email_content)


def send_email(receivers, subject, content, att_paths=None):
    server = 'smtp.exmail.qq.com'
    port = 25
    address = 'xxxx@xxx.com'
    password = 'xxxx'

    msg = MIMEMultipart()
    msg['Subject'] = Header(subject, 'utf-8')
    msg['From'] = formataddr(['GitLab', address])
    msg['To'] = receivers
    msg.attach(MIMEText(content, 'html', 'utf-8'))
    if att_paths is not None and len(att_paths) > 0:
        for att_path in att_paths:
            file = open(att_path, 'rb')
            file_name = basename(att_path)
            att = MIMEText(file.read(), 'base64', 'utf-8')
            att['Content-Type'] = 'application/octet-stream'
            att['Content-Disposition'] = 'attachment; filename = ' + file_name
            file.close()
            msg.attach(att)
    try:
        smtp = smtplib.SMTP()
        smtp.connect(server, port)
        smtp.login(address, password)
        smtp.sendmail(address, receivers.split(','), msg.as_string())
        smtp.quit()
    except smtplib.SMTPException as e:
        print(e)


if __name__ == '__main__':
    main()
