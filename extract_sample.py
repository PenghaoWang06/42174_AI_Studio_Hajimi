# Randomly pick some images from a zip file
# Written by: Penghao Wang

import zipfile
import os
import random

# Where the zip is and where to put the images
zip_path = './Hajimi/Dataset/voc_split.zip' 
output_folder = './dataset'

def sample_images_from_zip(zip_filepath, out_dir, sample_size=10):
    # Make the folder if it's not there
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

    print(f"Opening zip: {zip_filepath}...")
    
    try:
        with zipfile.ZipFile(zip_filepath, 'r') as zip_ref:
            # Get everything inside the zip
            all_files = zip_ref.namelist()
            
            # Just keep the images (png, jpg, jpeg)
            # Also need to ignore those weird Mac '._' files that cause errors
            images = [f for f in all_files if f.lower().endswith(('.png', '.jpg', '.jpeg')) 
                      and not os.path.basename(f).startswith('._')]
            
            if not images:
                print("No images found in the zip.")
                return

            # Pick 10 random files (or less if the zip is small)
            sampled_files = random.sample(images, min(sample_size, len(images)))
            
            # Extract them one by one
            for file_path in sampled_files:
                # Just get the filename, don't keep the long path folders
                file_name = os.path.basename(file_path)
                
                if file_name: 
                    # Write the image to our output folder
                    with zip_ref.open(file_path) as source, open(os.path.join(out_dir, file_name), "wb") as target:
                        target.write(source.read())
            
            print(f"Done! Saved {len(sampled_files)} images to {out_dir}")
            
    except Exception as e:
        # Just print the error if something goes wrong
        print(f"Error: {e}")

# Run the function to get 10 samples
sample_images_from_zip(zip_path, output_folder, 10)