import os
import requests
import json
import webvtt
import tiktoken
import time
import re

# --- 1. 配置区 ---

VTT_FOLDER_PATH = r'C:\Users\wwd_m\Downloads\test-vtt'
OUTPUT_FOLDER_PATH = r'C:\Users\wwd_m\Downloads\output-vtt-md'
API_URL = 'http://127.0.0.1:1234/v1/chat/completions'

# 【优化点1】: 尝试一个更大的分片值，您可以根据测试结果调整这个数字
MAX_TOKENS_PER_CHUNK = 2500  # 建议从 2500 开始测试

# 【优化点2】: 使用能合并段落的新版Prompt
SYSTEM_PROMPT = """
你是一位顶级的翻译家和内容编辑。
你的任务是：将用户提供的英文视频口播稿，完整地翻译成一篇流畅、自然、连贯的简体中文文章。

请严格遵守以下核心原则：
1. **全文翻译与合并**：
   - 必须逐句翻译所有内容，不能省略或总结。
   - **关键指令**：请智能地将原文中语义连贯的多行短句，合并成符合中文阅读习惯的自然段落。不要原文每行都换行。

2. **保持逻辑**：在合并段落时，要尊重原文的逻辑停顿。如果原文有明显的空行或意群转换，可以在译文中也进行分段。

3. **Markdown输出**：使用 Markdown 格式，可以对关键词进行 **加粗** 以提高可读性。

4. **直接输出文章**：请直接开始输出最终翻译好的中文文章，不要包含任何解释或类似 <think> 的标签。
"""

# --- 2. 核心功能区 (与上一版相同) ---

def get_tokenizer():
    try:
        return tiktoken.get_encoding("cl100k_base")
    except Exception as e:
        print(f"获取 tokenizer 失败: {e}")
        return None

def parse_vtt_file(file_path):
    try:
        captions = webvtt.read(file_path)
        full_text = "\n".join([caption.text.strip() for caption in captions])
        return full_text
    except Exception as e:
        print(f"解析VTT文件 {os.path.basename(file_path)} 时出错: {e}")
        return None

def split_text_into_chunks(text, tokenizer):
    if not tokenizer:
        print("Tokenizer 不可用，无法进行分片。将尝试一次性处理。")
        return [text]
    tokens = tokenizer.encode(text)
    if len(tokens) <= MAX_TOKENS_PER_CHUNK:
        return [text]

    print(f"文本过长 ({len(tokens)} tokens)，正在分片处理...")
    chunks = []
    current_chunk_tokens = []
    paragraphs = text.split('\n')
    for paragraph in paragraphs:
        if not paragraph.strip():
            continue
        paragraph_tokens = tokenizer.encode(paragraph + "\n")
        if len(current_chunk_tokens) + len(paragraph_tokens) > MAX_TOKENS_PER_CHUNK:
            if current_chunk_tokens:
                chunks.append(tokenizer.decode(current_chunk_tokens))
                current_chunk_tokens = []
        current_chunk_tokens.extend(paragraph_tokens)
    if current_chunk_tokens:
        chunks.append(tokenizer.decode(current_chunk_tokens))
    
    print(f"文本成功被分成了 {len(chunks)} 个片段。")
    return chunks

def clean_model_output(raw_text):
    cleaned_text = re.sub(r'^\s*<think>.*?</think>\s*', '', raw_text, flags=re.DOTALL)
    return cleaned_text

def process_chunk_with_llm(text_chunk):
    headers = {"Content-Type": "application/json"}
    payload = {
        "model": "local-model",
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text_chunk}
        ],
        "temperature": 0.7,
        "stream": False
    }
    try:
        response = requests.post(API_URL, headers=headers, data=json.dumps(payload), timeout=300)
        response.raise_for_status()
        response_json = response.json()
        raw_output_text = response_json['choices'][0]['message']['content']
        cleaned_output_text = clean_model_output(raw_output_text)
        return cleaned_output_text
    except requests.exceptions.Timeout:
        print(f"调用API时超时！(超过300秒)")
        return None
    except requests.exceptions.RequestException as e:
        print(f"调用API时出错: {e}")
        return None

def process_single_file(vtt_file_path, tokenizer):
    filename = os.path.basename(vtt_file_path)
    print(f"\n--- 正在处理文件: {filename} ---")
    
    english_text = parse_vtt_file(vtt_file_path)
    if not english_text:
        return

    chunks = split_text_into_chunks(english_text, tokenizer)
    
    processed_chunks = []
    for i, chunk in enumerate(chunks):
        print(f"正在翻译片段 {i+1}/{len(chunks)}...")
        translated_chunk = process_chunk_with_llm(chunk)
        if not translated_chunk:
            print(f"片段 {i+1} 翻译失败，已跳过整个文件 {filename}。")
            return
        processed_chunks.append(translated_chunk)
        time.sleep(1)
        
    final_text = "\n\n".join(processed_chunks)
    output_filename = f"{os.path.splitext(filename)[0]}.md"
    output_file_path = os.path.join(OUTPUT_FOLDER_PATH, output_filename)
    try:
        with open(output_file_path, 'w', encoding='utf-8') as f:
            f.write(final_text.strip())
        print(f"处理完成！翻译稿已保存至: {output_file_path}\n" + "-"*40)
    except IOError as e:
        print(f"保存文件 {output_filename} 时出错: {e}")

# --- 3. 主程序入口 ---
def main():
    if not os.path.isdir(VTT_FOLDER_PATH):
        print(f"错误：输入文件夹路径不存在 -> {VTT_FOLDER_PATH}")
        return
    if not os.path.isdir(OUTPUT_FOLDER_PATH):
        try:
            os.makedirs(OUTPUT_FOLDER_PATH)
            print(f"已自动创建输出文件夹: {OUTPUT_FOLDER_PATH}")
        except OSError as e:
            print(f"错误：无法创建输出文件夹 {OUTPUT_FOLDER_PATH}。错误信息: {e}")
            return
    tokenizer = get_tokenizer()
    for filename in sorted(os.listdir(VTT_FOLDER_PATH)):
        if filename.lower().endswith(".vtt"):
            vtt_file_path = os.path.join(VTT_FOLDER_PATH, filename)
            process_single_file(vtt_file_path, tokenizer)

if __name__ == '__main__':
    main()