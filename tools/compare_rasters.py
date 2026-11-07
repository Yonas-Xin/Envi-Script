"""
逐波段比对两幅 ENVI 栅格（如本工具结果与 ENVI 界面结果），输出差异统计。

- 按波长匹配波段（两幅波段数或顺序不同也可比对）；
- 两幅都有地理坐标且像元大小相同时按地图坐标对齐，否则按像元偏移对齐；
- 只统计两幅都有效的像元（排除无效值与 NaN）。

运行环境：conda 环境 geo（GDAL + NumPy）。在下方配置区填好路径后直接运行。
"""

import csv
import re
import sys
from pathlib import Path

import numpy as np
from osgeo import gdal

# ============================== 配置区 ==============================
FILE_A = "D:/AHSI/compare/script/scene_flaash.dat"   # 本工具结果
FILE_B = "D:/AHSI/compare/envi/scene_flaash.dat"     # ENVI 界面结果
LABEL_A = "脚本"
LABEL_B = "ENVI 界面"

ALIGN = "auto"            # auto：有地理坐标按地图坐标对齐，否则按像元偏移；map；pixel
PIXEL_OFFSET_B = (0, 0)   # ALIGN 为 pixel 时，A 的 (0,0) 对应 B 的 (列, 行)
SCALE_A = 1.0             # 统计前分别乘的系数（如把反射率 ×10000 统一到同一量纲）
SCALE_B = 1.0
IGNORE_VALUE = 0          # 无效值（两幅中任一为该值的像元不参与统计），None 表示不排除
WAVELENGTH_TOL_NM = 0.5   # 按波长匹配的容差

OUT_CSV = None            # 逐波段结果 CSV，None 表示与 FILE_A 同目录、自动命名
# ====================================================================

gdal.UseExceptions()


def read_wavelengths(path):
    """从 ENVI 头文件读取波长（nm）。"""
    hdr = Path(path).with_suffix(".hdr")
    if not hdr.exists():
        return None
    text = hdr.read_bytes().decode("gbk", errors="ignore")
    m = re.search(r"wavelength\s*=\s*\{([^}]*)\}", text, re.I)
    if not m:
        return None
    wl = np.array([float(v) for v in m.group(1).split(",") if v.strip()])
    unit = re.search(r"wavelength units\s*=\s*(\w+)", text, re.I)
    if unit and unit.group(1).lower().startswith("micro"):
        wl = wl * 1000.0
    return wl


def overlap_windows(ds_a, ds_b):
    """返回 A、B 的重叠窗口 (xoff, yoff, xsize, ysize)。"""
    ga, gb = ds_a.GetGeoTransform(), ds_b.GetGeoTransform()
    has_geo = ga != (0, 1, 0, 0, 0, 1) and gb != (0, 1, 0, 0, 0, 1)
    mode = ALIGN
    if mode == "auto":
        mode = "map" if has_geo and abs(ga[1] - gb[1]) < 1e-6 and abs(ga[5] - gb[5]) < 1e-6 else "pixel"
    if mode == "map":
        dx = (ga[0] - gb[0]) / gb[1]
        dy = (ga[3] - gb[3]) / gb[5]
        if abs(dx - round(dx)) > 0.01 or abs(dy - round(dy)) > 0.01:
            print(f"警告：两幅网格不对齐（偏移 {dx:.3f}, {dy:.3f} 像元），按四舍五入对齐")
        ox, oy = int(round(dx)), int(round(dy))
    else:
        ox, oy = PIXEL_OFFSET_B
    xa0, ya0 = max(0, -ox), max(0, -oy)
    xb0, yb0 = max(0, ox), max(0, oy)
    w = min(ds_a.RasterXSize - xa0, ds_b.RasterXSize - xb0)
    h = min(ds_a.RasterYSize - ya0, ds_b.RasterYSize - yb0)
    if w <= 0 or h <= 0:
        sys.exit("两幅影像没有重叠区域")
    return (xa0, ya0, w, h), (xb0, yb0, w, h), mode


def main():
    ds_a, ds_b = gdal.Open(FILE_A), gdal.Open(FILE_B)
    wa, wb = read_wavelengths(FILE_A), read_wavelengths(FILE_B)
    win_a, win_b, mode = overlap_windows(ds_a, ds_b)
    print(f"A: {FILE_A}\nB: {FILE_B}\n对齐方式: {mode}，重叠 {win_a[2]}x{win_a[3]} 像元")

    if wa is not None and wb is not None:
        pairs = []
        for i, w in enumerate(wa):
            j = int(np.argmin(np.abs(wb - w)))
            if abs(wb[j] - w) <= WAVELENGTH_TOL_NM:
                pairs.append((i, j, w))
    else:
        n = min(ds_a.RasterCount, ds_b.RasterCount)
        pairs = [(i, i, float("nan")) for i in range(n)]
    print(f"匹配波段 {len(pairs)} 个（A 共 {ds_a.RasterCount}，B 共 {ds_b.RasterCount}）")

    rows = []
    all_a, all_b = [], []
    for i, j, w in pairs:
        a = ds_a.GetRasterBand(i + 1).ReadAsArray(*win_a).astype(np.float64) * SCALE_A
        b = ds_b.GetRasterBand(j + 1).ReadAsArray(*win_b).astype(np.float64) * SCALE_B
        ok = np.isfinite(a) & np.isfinite(b)
        if IGNORE_VALUE is not None:
            ok &= (a != IGNORE_VALUE * SCALE_A) & (b != IGNORE_VALUE * SCALE_B)
        a, b = a[ok], b[ok]
        if a.size == 0:
            continue
        d = a - b
        denom = np.abs(b).mean()
        corr = np.corrcoef(a, b)[0, 1] if a.std() > 0 and b.std() > 0 else float("nan")
        rows.append({
            "band_a": i + 1, "band_b": j + 1, "wavelength_nm": round(w, 3),
            "n": a.size, "mean_a": a.mean(), "mean_b": b.mean(),
            "mean_diff": d.mean(), "mae": np.abs(d).mean(), "rmse": np.sqrt((d ** 2).mean()),
            "max_abs_diff": np.abs(d).max(), "rel_mae_pct": 100 * np.abs(d).mean() / denom if denom else float("nan"),
            "corr": corr,
        })
        sub = np.random.default_rng(0).choice(a.size, min(a.size, 2000), replace=False)
        all_a.append(a[sub])
        all_b.append(b[sub])

    out_csv = Path(OUT_CSV) if OUT_CSV else Path(FILE_A).with_name(Path(FILE_A).stem + "_vs_" + Path(FILE_B).stem + ".csv")
    with open(out_csv, "w", newline="", encoding="utf-8-sig") as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        wr.writeheader()
        wr.writerows(rows)

    mae = np.array([r["mae"] for r in rows])
    rel = np.array([r["rel_mae_pct"] for r in rows])
    mx = np.array([r["max_abs_diff"] for r in rows])
    corr = np.array([r["corr"] for r in rows])
    A, B = np.concatenate(all_a), np.concatenate(all_b)
    print(f"\n{LABEL_A} vs {LABEL_B}")
    print(f"  逐波段 MAE：中位数 {np.median(mae):.4g}，最大 {mae.max():.4g}（第 {rows[int(mae.argmax())]['band_a']} 波段）")
    print(f"  逐波段相对 MAE：中位数 {np.nanmedian(rel):.3f}%，最大 {np.nanmax(rel):.3f}%")
    print(f"  最大绝对差：{mx.max():.4g}")
    print(f"  逐波段相关系数：最小 {np.nanmin(corr):.6f}")
    print(f"  全部采样像元相关系数：{np.corrcoef(A, B)[0, 1]:.6f}")
    print(f"  完全一致的波段：{int((mx == 0).sum())}/{len(rows)}")
    print(f"逐波段结果：{out_csv}")


if __name__ == "__main__":
    main()
