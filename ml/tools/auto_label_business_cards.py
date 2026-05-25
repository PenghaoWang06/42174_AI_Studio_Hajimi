from __future__ import annotations

import argparse
import csv
import math
import os
import random
import shutil
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


@dataclass
class Detection:
    box: tuple[int, int, int, int]
    polygon: np.ndarray
    score: float
    method: str
    area_fraction: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create YOLO pre-labels for business card border detection."
    )
    parser.add_argument("--input", default="data/business_cards", help="Input image root.")
    parser.add_argument(
        "--output", default="data/business_cards_yolo", help="YOLO dataset output root."
    )
    parser.add_argument("--class-name", default="Business Card", help="YOLO class name.")
    parser.add_argument("--val-ratio", type=float, default=0.2, help="Validation split ratio.")
    parser.add_argument("--seed", type=int, default=42, help="Deterministic split seed.")
    parser.add_argument(
        "--preview-max-side",
        type=int,
        default=1200,
        help="Maximum preview image side length.",
    )
    return parser.parse_args()


def collect_images(input_root: Path, output_root: Path) -> list[Path]:
    output_root = output_root.resolve()
    images: list[Path] = []
    for path in input_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in IMAGE_EXTENSIONS:
            continue
        try:
            if output_root in path.resolve().parents:
                continue
        except OSError:
            pass
        images.append(path)
    return sorted(images, key=lambda p: str(p).lower())


def read_image(path: Path) -> np.ndarray | None:
    data = np.fromfile(str(path), dtype=np.uint8)
    if data.size == 0:
        return None
    return cv2.imdecode(data, cv2.IMREAD_COLOR)


def write_image(path: Path, image: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    success, encoded = cv2.imencode(path.suffix, image)
    if not success:
        raise RuntimeError(f"Could not encode image: {path}")
    encoded.tofile(str(path))


def resize_for_detection(image: np.ndarray, max_side: int = 1400) -> tuple[np.ndarray, float]:
    height, width = image.shape[:2]
    side = max(height, width)
    if side <= max_side:
        return image.copy(), 1.0
    scale = max_side / side
    resized = cv2.resize(
        image, (round(width * scale), round(height * scale)), interpolation=cv2.INTER_AREA
    )
    return resized, scale


def order_points(points: np.ndarray) -> np.ndarray:
    points = points.astype(np.float32)
    sums = points.sum(axis=1)
    diffs = np.diff(points, axis=1).reshape(-1)
    ordered = np.zeros((4, 2), dtype=np.float32)
    ordered[0] = points[np.argmin(sums)]
    ordered[2] = points[np.argmax(sums)]
    ordered[1] = points[np.argmin(diffs)]
    ordered[3] = points[np.argmax(diffs)]
    return ordered


def clamp_box(box: tuple[float, float, float, float], width: int, height: int) -> tuple[int, int, int, int]:
    x1, y1, x2, y2 = box
    x1 = max(0, min(width - 1, int(math.floor(x1))))
    y1 = max(0, min(height - 1, int(math.floor(y1))))
    x2 = max(0, min(width - 1, int(math.ceil(x2))))
    y2 = max(0, min(height - 1, int(math.ceil(y2))))
    if x2 <= x1:
        x2 = min(width - 1, x1 + 1)
    if y2 <= y1:
        y2 = min(height - 1, y1 + 1)
    return x1, y1, x2, y2


def mask_candidates(image: np.ndarray) -> list[tuple[str, np.ndarray]]:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)

    edges = cv2.Canny(gray, 35, 120)
    edge_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9))
    edge_mask = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, edge_kernel, iterations=2)
    edge_mask = cv2.dilate(edge_mask, edge_kernel, iterations=1)

    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    saturation = hsv[:, :, 1]
    value = hsv[:, :, 2]
    white_mask = np.zeros_like(gray)
    white_mask[(value > 120) & (saturation < 115)] = 255
    white_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (15, 15))
    white_mask = cv2.morphologyEx(white_mask, cv2.MORPH_CLOSE, white_kernel, iterations=2)
    white_mask = cv2.morphologyEx(white_mask, cv2.MORPH_OPEN, white_kernel, iterations=1)

    _, otsu_light = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    otsu_light = cv2.morphologyEx(otsu_light, cv2.MORPH_CLOSE, white_kernel, iterations=2)

    _, otsu_dark = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    otsu_dark = cv2.morphologyEx(otsu_dark, cv2.MORPH_CLOSE, white_kernel, iterations=2)

    return [
        ("edge", edge_mask),
        ("white", white_mask),
        ("otsu_light", otsu_light),
        ("otsu_dark", otsu_dark),
    ]


def contour_detection(image: np.ndarray) -> Detection | None:
    height, width = image.shape[:2]
    image_area = width * height
    detections: list[Detection] = []

    for method, mask in mask_candidates(image):
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        for contour in contours:
            contour_area = abs(cv2.contourArea(contour))
            if contour_area < image_area * 0.015:
                continue

            rect = cv2.minAreaRect(contour)
            rect_width, rect_height = rect[1]
            if rect_width < 5 or rect_height < 5:
                continue

            rect_area = rect_width * rect_height
            area_fraction = rect_area / image_area
            if area_fraction < 0.03 or area_fraction > 1.15:
                continue

            aspect = max(rect_width, rect_height) / max(1.0, min(rect_width, rect_height))
            if aspect < 1.05 or aspect > 4.5:
                continue

            polygon = cv2.boxPoints(rect)
            polygon = order_points(polygon)
            x, y, w, h = cv2.boundingRect(polygon.astype(np.int32))
            box = clamp_box((x, y, x + w, y + h), width, height)

            rectangularity = min(1.0, contour_area / max(1.0, rect_area))
            aspect_score = math.exp(-abs(aspect - 1.75) / 1.0)
            area_score = min(1.0, area_fraction / 0.45)
            margin_penalty = 0.0
            if area_fraction > 0.96:
                margin_penalty = 0.08

            perimeter = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.025 * perimeter, True)
            quad_bonus = 0.12 if len(approx) == 4 and cv2.isContourConvex(approx) else 0.0

            score = (
                0.40 * area_score
                + 0.25 * rectangularity
                + 0.23 * aspect_score
                + quad_bonus
                - margin_penalty
            )
            detections.append(
                Detection(
                    box=box,
                    polygon=polygon,
                    score=score,
                    method=method,
                    area_fraction=area_fraction,
                )
            )

    if not detections:
        return None
    return max(detections, key=lambda candidate: candidate.score)


def fallback_detection(image: np.ndarray) -> Detection:
    height, width = image.shape[:2]
    margin_x = round(width * 0.01)
    margin_y = round(height * 0.01)
    box = clamp_box((margin_x, margin_y, width - margin_x, height - margin_y), width, height)
    x1, y1, x2, y2 = box
    polygon = np.array([[x1, y1], [x2, y1], [x2, y2], [x1, y2]], dtype=np.float32)
    return Detection(box=box, polygon=polygon, score=0.0, method="fallback_full_image", area_fraction=1.0)


def detect_card(image: np.ndarray) -> Detection:
    resized, scale = resize_for_detection(image)
    detection = contour_detection(resized)
    if detection is None:
        return fallback_detection(image)

    if scale != 1.0:
        inv_scale = 1.0 / scale
        polygon = detection.polygon * inv_scale
        height, width = image.shape[:2]
        x1 = float(np.min(polygon[:, 0]))
        y1 = float(np.min(polygon[:, 1]))
        x2 = float(np.max(polygon[:, 0]))
        y2 = float(np.max(polygon[:, 1]))
        box = clamp_box((x1, y1, x2, y2), width, height)
        detection = Detection(
            box=box,
            polygon=polygon,
            score=detection.score,
            method=detection.method,
            area_fraction=detection.area_fraction,
        )
    return detection


def yolo_bbox_line(box: tuple[int, int, int, int], width: int, height: int, class_id: int = 0) -> str:
    x1, y1, x2, y2 = box
    x_center = ((x1 + x2) / 2.0) / width
    y_center = ((y1 + y2) / 2.0) / height
    box_width = (x2 - x1) / width
    box_height = (y2 - y1) / height
    values = [x_center, y_center, box_width, box_height]
    values = [max(0.0, min(1.0, value)) for value in values]
    return f"{class_id} " + " ".join(f"{value:.6f}" for value in values)


def make_unique_name(path: Path, input_root: Path, used: set[str]) -> str:
    relative = path.relative_to(input_root)
    stem = "_".join(relative.with_suffix("").parts)
    name = f"{stem}{path.suffix.lower()}"
    index = 2
    while name.lower() in used:
        name = f"{stem}_{index}{path.suffix.lower()}"
        index += 1
    used.add(name.lower())
    return name


def link_or_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if destination.stat().st_size == source.stat().st_size:
            return
        destination.unlink()
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def draw_preview(image: np.ndarray, detection: Detection, source_name: str, max_side: int) -> np.ndarray:
    preview = image.copy()
    x1, y1, x2, y2 = detection.box
    cv2.rectangle(preview, (x1, y1), (x2, y2), (0, 220, 0), max(3, round(max(image.shape[:2]) / 350)))
    polygon = detection.polygon.astype(np.int32).reshape((-1, 1, 2))
    cv2.polylines(preview, [polygon], True, (0, 130, 255), max(2, round(max(image.shape[:2]) / 500)))

    label = f"{source_name} | {detection.method} | score {detection.score:.2f}"
    font_scale = max(0.7, max(image.shape[:2]) / 1800)
    thickness = max(2, round(font_scale * 2))
    cv2.putText(
        preview,
        label,
        (20, 45),
        cv2.FONT_HERSHEY_SIMPLEX,
        font_scale,
        (0, 0, 0),
        thickness + 3,
        cv2.LINE_AA,
    )
    cv2.putText(
        preview,
        label,
        (20, 45),
        cv2.FONT_HERSHEY_SIMPLEX,
        font_scale,
        (255, 255, 255),
        thickness,
        cv2.LINE_AA,
    )

    height, width = preview.shape[:2]
    side = max(height, width)
    if side > max_side:
        scale = max_side / side
        preview = cv2.resize(
            preview, (round(width * scale), round(height * scale)), interpolation=cv2.INTER_AREA
        )
    return preview


def make_preview_sheet(preview_paths: list[Path], output_path: Path, tile_width: int = 360) -> None:
    if not preview_paths:
        return

    images = []
    for path in preview_paths[:24]:
        image = read_image(path)
        if image is None:
            continue
        height, width = image.shape[:2]
        scale = tile_width / width
        tile_height = max(1, round(height * scale))
        images.append(cv2.resize(image, (tile_width, tile_height), interpolation=cv2.INTER_AREA))

    if not images:
        return

    columns = 4
    rows = math.ceil(len(images) / columns)
    tile_height = max(image.shape[0] for image in images)
    sheet = np.full((rows * tile_height, columns * tile_width, 3), 245, dtype=np.uint8)

    for index, image in enumerate(images):
        row = index // columns
        column = index % columns
        y = row * tile_height
        x = column * tile_width
        sheet[y : y + image.shape[0], x : x + image.shape[1]] = image

    write_image(output_path, sheet)


def write_yaml(path: Path, dataset_root: Path, class_name: str) -> None:
    yaml_text = "\n".join(
        [
            f"path: {dataset_root.resolve().as_posix()}",
            "train: images/train",
            "val: images/val",
            "names:",
            f"  0: {class_name}",
            "",
        ]
    )
    path.write_text(yaml_text, encoding="utf-8")


def split_images(images: list[Path], val_ratio: float, seed: int) -> dict[Path, str]:
    groups: dict[str, list[Path]] = {}
    for path in images:
        groups.setdefault(path.parent.name, []).append(path)

    rng = random.Random(seed)
    splits: dict[Path, str] = {}
    for group_images in groups.values():
        group_images = sorted(group_images, key=lambda p: str(p).lower())
        rng.shuffle(group_images)
        val_count = max(1, round(len(group_images) * val_ratio)) if len(group_images) > 1 else 0
        val_items = set(group_images[:val_count])
        for path in group_images:
            splits[path] = "val" if path in val_items else "train"
    return splits


def main() -> None:
    args = parse_args()
    input_root = Path(args.input)
    output_root = Path(args.output)

    images = collect_images(input_root, output_root)
    if not images:
        raise SystemExit(f"No images found under {input_root}")

    splits = split_images(images, args.val_ratio, args.seed)
    report_path = output_root / "annotations.csv"
    yaml_path = output_root / "business_cards_yolo.yaml"
    report_path.parent.mkdir(parents=True, exist_ok=True)

    used_names: set[str] = set()
    rows: list[dict[str, object]] = []
    preview_paths: list[Path] = []
    group_preview_paths: dict[str, list[Path]] = {}

    for source_path in images:
        image = read_image(source_path)
        if image is None:
            rows.append({"source": str(source_path), "status": "unreadable"})
            continue

        height, width = image.shape[:2]
        split = splits[source_path]
        output_name = make_unique_name(source_path, input_root, used_names)
        image_path = output_root / "images" / split / output_name
        label_path = output_root / "labels" / split / Path(output_name).with_suffix(".txt")
        preview_path = output_root / "previews" / split / Path(output_name).with_suffix(".jpg")

        detection = detect_card(image)
        link_or_copy(source_path, image_path)

        label_path.parent.mkdir(parents=True, exist_ok=True)
        label_path.write_text(yolo_bbox_line(detection.box, width, height) + "\n", encoding="utf-8")

        preview = draw_preview(image, detection, output_name, args.preview_max_side)
        write_image(preview_path, preview)
        preview_paths.append(preview_path)
        group_preview_paths.setdefault(source_path.parent.name, []).append(preview_path)

        x1, y1, x2, y2 = detection.box
        rows.append(
            {
                "source": str(source_path),
                "output_image": str(image_path),
                "label": str(label_path),
                "preview": str(preview_path),
                "split": split,
                "width": width,
                "height": height,
                "x1": x1,
                "y1": y1,
                "x2": x2,
                "y2": y2,
                "method": detection.method,
                "score": f"{detection.score:.4f}",
                "area_fraction": f"{detection.area_fraction:.4f}",
                "status": "ok",
            }
        )

    fieldnames = [
        "source",
        "output_image",
        "label",
        "preview",
        "split",
        "width",
        "height",
        "x1",
        "y1",
        "x2",
        "y2",
        "method",
        "score",
        "area_fraction",
        "status",
    ]
    with report_path.open("w", newline="", encoding="utf-8") as report_file:
        writer = csv.DictWriter(report_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    write_yaml(yaml_path, output_root, args.class_name)
    make_preview_sheet(preview_paths, output_root / "preview_sheet.jpg")
    for group_name, paths in sorted(group_preview_paths.items()):
        make_preview_sheet(paths, output_root / f"preview_sheet_{group_name}.jpg")

    ok_count = sum(1 for row in rows if row.get("status") == "ok")
    fallback_count = sum(1 for row in rows if row.get("method") == "fallback_full_image")
    print(f"Images: {len(images)}")
    print(f"Labeled: {ok_count}")
    print(f"Fallback full-image labels: {fallback_count}")
    print(f"Dataset YAML: {yaml_path}")
    print(f"Report: {report_path}")
    print(f"Preview sheet: {output_root / 'preview_sheet.jpg'}")


if __name__ == "__main__":
    main()
