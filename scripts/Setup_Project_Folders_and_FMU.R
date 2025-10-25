# =====================================================
# 0️⃣ Identify and verify project directory
# =====================================================
getwd()
# مسیر کاری فعلی را شناسایی کن

# در صورت تمایل می‌توانی مسیر را به‌صورت دستی هم مشخص کنی (اختیاری)
proj_dir <- "E:/MyProjects/ON_Sudbury_LandR"

# نمایش مسیر برای اطمینان
message("📁 Current working directory set to:\n", proj_dir)

# بررسی اینکه پوشه واقعاً وجود دارد
if (!dir.exists(proj_dir)) {
  stop("❌ Project directory does not exist. Please check your path.")
}

# ایجاد مسیر پیش‌فرض برای زیرپوشه‌ها
setwd(proj_dir)

# =====================================================
# Step 1: Create LandR project folder structure
# =====================================================

library(fs)

dirs <- c(
  "data",          # داده‌های خام (مثل shapefileها)
  "inputs",        # داده‌های پردازش‌شده برای مدل‌ها
  "outputs",       # خروجی‌های شبیه‌سازی‌ها
  "modules",       # ماژول‌های SpaDES
  "scripts",       # Global و StudyArea اسکریپت‌ها
  "cache",         # کش reproducible
  "BOUNDARIES"     # مرز FMUها (مثل Sudbury)
)

dir_create(dirs)
list.dirs(".", recursive = FALSE)
# =====================================================
# Step 2: Download & extract FRI Status shapefile (Ontario FMUs)
# =====================================================

library(curl)
library(fs)
library(archive)
library(sf)


# مسیر دانلود و استخراج
zip_path <- file.path(proj_dir, "data", "FRI_STATUS_ON.zip")
unzip_dir <- file.path(proj_dir, "data", "FRI_STATUS_ON")
dir_create(unzip_dir)

# لینک مستقیم shapefile FMUها
url <- "https://hub.arcgis.com/api/v3/datasets/4e3cdfdb8fe74f33af4aa51238b92538_23/downloads/data?format=shp&spatialRefId=4269&where=1%3D1"

# دانلود
curl_download(url, destfile = zip_path, quiet = FALSE)

# باز کردن فایل زیپ
archive_extract(zip_path, dir = unzip_dir)

# مسیر shapefile
shp_path <- file.path(unzip_dir, "FRI_Status.shp")

# =====================================================
# Step 3: Select Sudbury FMU
# =====================================================

fmu <- st_read(shp_path, quiet = TRUE)
sudbury <- fmu[fmu$FRI_UNIT_N == "Sudbury Forest", ]

# Reproject to EPSG:5070 (NAD83 / Conus Albers)
sudbury_5070 <- st_transform(sudbury, 5070)

# Save clipped shapefile
out_path <- file.path(proj_dir, "BOUNDARIES", "Sudbury_FMU_5070.shp")
st_write(sudbury_5070, out_path, delete_layer = TRUE)

cat("\n✅ Saved Sudbury shapefile at:\n", out_path, "\n")
# =====================================================
# =====================================================
# Step 4: Land Cover – Canada (CEC 2020 v2 – lightweight version)
# =====================================================

library(curl)
library(archive)
library(terra)
library(fs)

dirs$landcover_ca <- file.path(proj_dir, "LandCover_Canada")
dir_create(dirs$landcover_ca)

# لینک رسمی CEC (North American Land Cover 2020 v2, 30m)
lcc_url <- "https://www.cec.org/files/atlas_layers/1_terrestrial_ecosystems/1_01_0_land_cover_2020_30m/land_cover_2020v2_30m_tif.zip"

# مسیر فایل فشرده و خروجی
zip_path <- file.path(dirs$landcover_ca, basename(lcc_url))
tif_path <- file.path(dirs$landcover_ca, "land_cover_2020v2_30m.tif")

# اگر فایل هنوز دانلود نشده، دانلود کن
if (!file.exists(tif_path)) {
  message("⬇️ Downloading CEC Land Cover 2020v2 ...")
  curl_download(lcc_url, destfile = zip_path, quiet = FALSE)
  message("✅ Download complete. Extracting...")
  archive_extract(zip_path, dir = dirs$landcover_ca)
}

# اطمینان از نام درست فایل
if (!file.exists(tif_path)) {
  possible_tif <- list.files(dirs$landcover_ca, pattern = "tif$", full.names = TRUE)
  file.rename(possible_tif[1], tif_path)
}

# بارگذاری نقشه
# =====================================================
# Step 4b: Find the extracted TIFF file automatically
# =====================================================

library(fs)
library(terra)

# جستجو در پوشه LandCover_Canada برای هر فایل با پسوند tif
possible_tifs <- dir(
  path = dirs$landcover_ca,
  pattern = "\\.tif$",
  recursive = TRUE,
  full.names = TRUE
)

# انتخاب اولین فایل بزرگ‌تر از 100MB (تا فایل‌های موقت حذف شن)
tif_sizes <- file.info(possible_tifs)$size
tif_candidates <- possible_tifs[tif_sizes > 1e8]

if (length(tif_candidates) == 0) {
  stop("❌ No valid TIFF found in LandCover_Canada. Please check the extraction.")
} else {
  tif_path <- tif_candidates[1]
  message("✅ Found landcover file:\n", tif_path)
}

# بارگذاری و نمایش
r_ca <- terra::rast(tif_path)
terra::plot(r_ca, main = "CEC Land Cover 2020v2 (Canada)")




# =====================================================
# Step 5 (Optimized): Clip LandCover to Sudbury FMU
# =====================================================

# shapefile Sudbury را بخوانیم
sudbury_fmu <- terra::vect(out_path)

# گام 1: ابتدا shapefile را به CRS لندکاور (NAD83) تبدیل کن تا crop سریع شود
if (terra::crs(sudbury_fmu) != terra::crs(r_ca)) {
  message("🔄 Reprojecting Sudbury shapefile to match LandCover CRS (for fast cropping)...")
  sudbury_fmu_nad83 <- terra::project(sudbury_fmu, terra::crs(r_ca))
} else {
  sudbury_fmu_nad83 <- sudbury_fmu
}

# گام 2: فقط محدوده‌ی Sudbury را از نقشه اصلی ببُر
message("✂️ Cropping LandCover to Sudbury extent (fast method)...")
r_sudbury_temp <- terra::crop(r_ca, sudbury_fmu_nad83)

# گام 3: حالا آن تکه کوچک را به CRS Sudbury (EPSG:5070) برگردان
message("🔄 Reprojecting cropped raster to EPSG:5070 ...")
r_sudbury <- terra::project(r_sudbury_temp, terra::crs(sudbury_fmu))

# گام 4: ماسک نهایی فقط درون مرز Sudbury
message("🎯 Applying mask for Sudbury FMU boundary ...")
r_sudbury <- terra::mask(r_sudbury, sudbury_fmu)

# گام 5: ذخیره فایل خروجی
lcc_clip_path <- file.path(dirs$landcover_ca, "LCC2020v2_Sudbury_30m.tif")
terra::writeRaster(r_sudbury, lcc_clip_path, overwrite = TRUE)

message("✅ Saved clipped LandCover at:\n", lcc_clip_path)

# نمایش نقشه خروجی
terra::plot(r_sudbury, main = "Sudbury FMU – CEC Land Cover 2020v2 (30m)")



