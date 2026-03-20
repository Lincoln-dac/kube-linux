#!/usr/bin/env python2
# -*- coding: utf-8 -*-

import os
import sys
import yaml
import shutil

# 输入输出目录
INPUT_DIR = "/tmp/prd"
OUTPUT_DIR = "/tmp/uat"

# 需要修改的键值对映射（环境变量名 -> 目标值）
ENV_UPDATES = {
    "SPRING_PROFILES": "UAT",
    "DISCONF_SERVER": "disconf-uat.fcbox.com",
    "FC_ENCRYPT_KEY": "NZ04YbkaKRIxiLLU"
}

def ensure_dir(path):
    """确保目录存在，若不存在则创建"""
    if not os.path.exists(path):
        os.makedirs(path)

def update_deployment_name(obj, old_name, new_name):
    """递归替换字典/列表中所有等于 old_name 的字符串为 new_name（仅用于特定字段）"""
    # 为避免误替换，我们只针对已知字段进行精确替换
    # 该方法会在后续的特定字段处理中调用，不用于全局递归
    pass

def process_deployment(doc, filename):
    """
    处理单个 Deployment 文档
    :param doc: 解析后的 YAML 字典
    :param filename: 原始文件名（仅用于错误提示）
    :return: 修改后的文档和新文件名（不含路径）
    """
    if not isinstance(doc, dict) or doc.get("kind") != "Deployment":
        print "警告: {} 不是一个 Deployment，跳过".format(filename)
        return None, None

    # 获取原 deployment 名称
    old_name = doc.get("metadata", {}).get("name")
    if not old_name:
        print "错误: {} 中未找到 metadata.name，跳过".format(filename)
        return None, None

    new_name = old_name + "-uat"
    print "处理 {} -> {}".format(old_name, new_name)

    # ----- 1. 替换 metadata.name -----
    doc["metadata"]["name"] = new_name

    # ----- 2. 替换 selector.matchLabels.app -----
    selector = doc.get("spec", {}).get("selector", {})
    match_labels = selector.get("matchLabels", {})
    if match_labels.get("app") == old_name:
        match_labels["app"] = new_name

    # ----- 3. 替换 template.metadata.labels.app -----
    template = doc.get("spec", {}).get("template", {})
    labels = template.get("metadata", {}).get("labels", {})
    if labels.get("app") == old_name:
        labels["app"] = new_name

    # ----- 4. 修改环境变量（所有容器）-----
    containers = template.get("spec", {}).get("containers", [])
    for container in containers:
        env_list = container.get("env", [])
        for env in env_list:
            name = env.get("name")
            # 替换 APP_NAME（如果存在且值为旧名称）
            if name == "APP_NAME" and env.get("value") == old_name:
                env["value"] = new_name
            # 根据 ENV_UPDATES 修改其他指定环境变量
            if name in ENV_UPDATES:
                env["value"] = ENV_UPDATES[name]
        # JAVA_OPTS 保持不变，无需处理

    # ----- 5. 修改 replicas 为 2 -----
    doc["spec"]["replicas"] = 2

    # ----- 6. 添加 nodeSelector Zone: uat -----
    pod_spec = template.get("spec", {})
    if "nodeSelector" not in pod_spec:
        pod_spec["nodeSelector"] = {}
    pod_spec["nodeSelector"]["Zone"] = "uat"

    # 新文件名：原deployment名称 + "-uat.yaml"
    new_filename = old_name + "-uat.yaml"
    return doc, new_filename

def main():
    ensure_dir(OUTPUT_DIR)

    for fname in os.listdir(INPUT_DIR):
        if not (fname.endswith(".yaml") or fname.endswith(".yml")):
            continue
        in_path = os.path.join(INPUT_DIR, fname)
        with open(in_path, 'r') as f:
            try:
                # 加载 YAML（支持多个文档，但这里假设每个文件只有一个 Deployment）
                docs = list(yaml.safe_load_all(f))
            except yaml.YAMLError as e:
                print "YAML 解析失败 {}: {}".format(fname, e)
                continue

        # 处理每个文档（通常只有一个）
        out_docs = []
        for doc in docs:
            if doc is None:
                continue
            new_doc, new_fname = process_deployment(doc, fname)
            if new_doc:
                out_docs.append(new_doc)

        if not out_docs:
            continue

        # 写入输出文件
        out_path = os.path.join(OUTPUT_DIR, new_fname)
        with open(out_path, 'w') as f:
            if len(out_docs) == 1:
                yaml.safe_dump(out_docs[0], f, default_flow_style=False, allow_unicode=True)
            else:
                yaml.safe_dump_all(out_docs, f, default_flow_style=False, allow_unicode=True)
        print "已生成: {}".format(out_path)

if __name__ == "__main__":
    main()