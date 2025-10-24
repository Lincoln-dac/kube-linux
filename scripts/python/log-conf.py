# /usr/bin/env python
# coding: utf-8
# description: filebeat自动配置脚本
#
# 日志文件路径:
#    - /app/applogs/服务/日志文件.log
#    - /app/applogs/服务/子目录/日志文件.log
#
# topic命名规则:
#    - 小写
#    - k8s-服务名-日志文件名
#    - k8s-服务名-子目录名-日志文件名
#
# es索引命名规则: topic-20190101


import os
import re
import sys
import logging
import argparse
import threading
import time
import yaml
from queue import Queue
from pyinotify import WatchManager, Notifier, IN_CREATE

#multiline.pattern: '^\d{4}-\d{1,2}\-\d{1,2}\s\d{2}:\d{2}:\d{2}.\d{3}'
#multiline.negate: true
#multiline.match: after
class ConfigUpdater:

    def __init__(self, filepath, rootpath=None):
        self.file = filepath
        self.root = os.path.abspath(rootpath) if rootpath else ""
        self.tmpl = dict(
            type="log",
            encoding="plain",
            fields_under_root=True,
            clean_inactive="25h",
            close_inactive="2h",
            ignore_older="24h",
            scan_frequency="1s",
            harvester_buffer_size=16384,
            max_bytes=10485760,
            backoff="1s",
            max_backoff="10s",
            backoff_factor=2,
            force_close_files=False,
            tail_files=True,
            multiline=dict(
                pattern=r'^\d{4}\-\d{1,2}\-\d{1,2}\s\d{2}:\d{2}:\d{2}.\d{3}\s\001',
                negate=True,
                match="after"
            )
        )

    def update(self, event):
        logpath = event.pathname
        logname = event.name.replace("-", "_")
        subdirs = event.path.replace(self.root, "", 1).replace("-", "_").split("/")
        if subdirs[0] == "":
            subdirs.pop(0)
        suffix = logname
        if subdirs:
            suffix = "%s-%s" % ("-".join(subdirs), suffix)
        topic = "k8s-" + suffix
        self.__write_to_yaml(logpath, topic)

    def __exists(self, content, log):
        if content:
            for item in content:
                if log in item["paths"]:
                    logging.info("配置已存在，忽略: path=%s" % log)
                    return True
        return False

    def __write_to_yaml(self, logpath, topic):
        topic = topic.lower()
        try:
            with open(self.file, "r+") as f:
                content = yaml.safe_load(f.read())
                if not self.__exists(content, logpath):
                    self.tmpl["paths"] = [logpath]
                    self.tmpl["fields"] = {"target_topic": topic, "NODE_IP": "${HOST_IP}"}
                    new_source = [self.tmpl]
                    f.write("\n")
                    f.write(yaml.dump(new_source))
                    logging.info("更新配置: log=%s, topic=%s" % (logpath, topic))
        except Exception as e:
            logging.error("更新配置失败: %s" % str(e))


class Watcher:
    def __init__(self, configfile, logdir):
        self.configfile = configfile
        self.logdir = logdir

        self.__queue = Queue()
        self.__add_watch()

        self.cfg = ConfigUpdater(self.configfile, self.logdir)

    def __add_watch(self):
        mask = IN_CREATE
        wm = WatchManager()
        self._notifier = Notifier(wm)
        wm.add_watch(self.logdir, mask, self.__event_queue, rec=True, auto_add=True)

    def __event_queue(self, event):
        self.__queue.put(event)

    def watcher(self):
        while True:
            self._notifier.process_events()
            if self._notifier.check_events():
                self._notifier.read_events()

    def handler(self):
        while True:
            if self.__queue.empty():
                time.sleep(0.1)
                continue

            event = self.__queue.get()
            if not event.dir and self.__check_ok(event.name):
                self.cfg.update(event)

    def __check_ok(self, name):
        #if not name.endswith(".log"):
        #    return False
        if re.match(r'^\S+\d{4}[-_.]?\d{2}[-_.]?\d{2}.*.log$', name):
            return False
        if re.match(r'^[a-zA-Z0-9]+[a-zA-Z0-9-_.]+.log$', name):
            return True
        if re.match(r'^traefik.*.log.*$', name):
            return False
        else:
            return False

    def run_forever(self):
        t1 = threading.Thread(target=self.watcher, name="watcher")
        t2 = threading.Thread(target=self.handler, name="handler")
        t1.setDaemon(True)
        t2.setDaemon(True)

        t2.start()
        t1.start()

        while True:
            try:
                time.sleep(1)
            except KeyboardInterrupt:
                sys.exit(0)


if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s [%(levelname)s] %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S",
                        level=logging.INFO)

    parser = argparse.ArgumentParser(description="filebeat 日志采集自动配置工具")
    parser.add_argument("-c", dest="config", help="filebeat配置文件路径", required=True)
    parser.add_argument("-d", dest="dir", help="监听日志目录", required=True)
    # parser.add_argument("-p", dest="pattern", help="监听日志文件名, 支持正则", required=False, action="append")

    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)

    args = parser.parse_args()

    if not os.path.isfile(args.config):
        logging.critical("文件不存在: %s" % args.config)
        sys.exit(2)
    if not os.path.isdir(args.dir):
        logging.critical("目录不存在: %s" % args.dir)
        sys.exit(2)

    watcher = Watcher(args.config, args.dir)
    watcher.run_forever()
