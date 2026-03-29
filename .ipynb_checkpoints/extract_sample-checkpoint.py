# Hajimi Team: Random Data Sampler from ZIP
# Author: Penghao Wang (Data Engineer)

import zipfile
import os
import random

# 根据你的截图，Zip文件的路径在这里
zip_path = './Hajimi/Dataset/voc_split.zip' 
output_folder = './dataset'

def sample_images_from_zip(zip_filepath, out_dir, sample_size=10):
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

    print(f"Reading zip file: {zip_filepath}...")
    
    try:
        with zipfile.ZipFile(zip_filepath, 'r') as zip_ref:
            # 获取压缩包里所有的文件名
            all_files = zip_ref.namelist()
            
            # 过滤出图片文件 (jpg, png)
            # 过滤出图片文件，并且坚决不要 Mac 产生的 '._' 开头的幽灵文件
images = [f for f in all_files if f.lower().endswith(('.png', '.jpg', '.jpeg')) and not os.path.basename(f).startswith('._')]
            
            if not images:
                print("Error: 压缩包里没有找到图片！")
                return

            # 随机抽取 10 张
            sampled_files = random.sample(images, min(sample_size, len(images)))
            
            # 把这 10 张图提取到 dataset 文件夹，并去掉原来复杂的子文件夹层级
            for file_path in sampled_files:
                file_name = os.path.basename(file_path)
                if file_name: # 确保不是空文件夹
                    with zip_ref.open(file_path) as source, open(os.path.join(out_dir, file_name), "wb") as target:
                        target.write(source.read())
            
            print(f"Success! 成功抽取 {len(sampled_files)} 张随机图片并存入 {out_dir} 文件夹。")
            
    except Exception as e:
        print(f"解压出错: {e}")

# 运行函数
sample_images_from_zip(zip_path, output_folder, 10)