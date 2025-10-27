# =====================================================
# 0️⃣ Identify and verify project directory
# =====================================================
getwd()

# Identify current working directory
# (You can manually set it below if needed)
proj_dir <- "E:/MyProjects/ON_Sudbury_LandR"

# Print the active working directory
message("📁 Current working directory set to:\n", proj_dir)

# Check if the directory actually exists
if (!dir.exists(proj_dir)) {
  stop("❌ Project directory does not exist. Please check your path.")
}

# Set working directory
setwd(proj_dir)

# =====================================================
# Step 1: Create LandR project folder structure
# =====================================================

library(fs)

dirs <- c(
  "data",          # Raw data (e.g., shapefiles)
  "inputs",        # Preprocessed data used in models
  "outputs",       # Simulation outputs
  "modules",       # SpaDES modules
  "scripts",       # Global and StudyArea scripts
  "cache",         # Reproducible cache
  "BOUNDARIES"     # FMU boundaries (e.g., Sudbury)
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

# Define download and extraction paths
zip_path <- file.path(proj_dir, "data", "FRI_STATUS_ON.zip")
unzip_dir <- file.path(proj_dir, "data", "FRI_STATUS_ON")
dir_create(unzip_dir)

# Direct link to FMU shapefile
url <- "https://hub.arcgis.com/api/v3/datasets/4e3cdfdb8fe74f33af4aa51238b92538_23/downloads/data?format=shp&spatialRefId=4269&where=1%3D1"

# Download the shapefile
curl_download(url, destfile = zip_path, quiet = FALSE)

# Extract ZIP file
archive_extract(zip_path, dir = unzip_dir)

# Define shapefile path
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
# Step 4: Land Cover – Canada (CEC 2020 v2 – lightweight version)
# =====================================================

library(curl)
library(archive)
library(terra)
library(fs)

dirs$landcover_ca <- file.path(proj_dir, "LandCover_Canada")
dir_create(dirs$landcover_ca)

# Official CEC link (North American Land Cover 2020 v2, 30m)
lcc_url <- "https://www.cec.org/files/atlas_layers/1_terrestrial_ecosystems/1_01_0_land_cover_2020_30m/land_cover_2020v2_30m_tif.zip"

# Define paths for ZIP and extracted TIFF
zip_path <- file.path(dirs$landcover_ca, basename(lcc_url))
tif_path <- file.path(dirs$landcover_ca, "land_cover_2020v2_30m.tif")

# Download if file doesn’t exist yet
if (!file.exists(tif_path)) {
  message("⬇️ Downloading CEC Land Cover 2020v2 ...")
  curl_download(lcc_url, destfile = zip_path, quiet = FALSE)
  message("✅ Download complete. Extracting...")
  archive_extract(zip_path, dir = dirs$landcover_ca)
}

# Ensure TIFF file has the correct name
if (!file.exists(tif_path)) {
  possible_tif <- list.files(dirs$landcover_ca, pattern = "tif$", full.names = TRUE)
  file.rename(possible_tif[1], tif_path)
}

# =====================================================
# Step 4b: Find the extracted TIFF file automatically
# =====================================================

library(fs)
library(terra)

# Search for any TIFF file in the LandCover_Canada directory
possible_tifs <- dir(
  path = dirs$landcover_ca,
  pattern = "\\.tif$",
  recursive = TRUE,
  full.names = TRUE
)

# Select the first large TIFF (>100 MB) to avoid temp files
tif_sizes <- file.info(possible_tifs)$size
tif_candidates <- possible_tifs[tif_sizes > 1e8]

if (length(tif_candidates) == 0) {
  stop("❌ No valid TIFF found in LandCover_Canada. Please check the extraction.")
} else {
  tif_path <- tif_candidates[1]
  message("✅ Found landcover file:\n", tif_path)
}

# Load and preview raster
r_ca <- terra::rast(tif_path)
terra::plot(r_ca, main = "CEC Land Cover 2020v2 (Canada)")

# =====================================================
# Step 5 (Optimized): Clip LandCover to Sudbury FMU
# =====================================================

# Read Sudbury shapefile
sudbury_fmu <- terra::vect(out_path)

# Step 1: Reproject Sudbury shapefile to match LandCover CRS (for faster cropping)
if (terra::crs(sudbury_fmu) != terra::crs(r_ca)) {
  message("🔄 Reprojecting Sudbury shapefile to match LandCover CRS (for fast cropping)...")
  sudbury_fmu_nad83 <- terra::project(sudbury_fmu, terra::crs(r_ca))
} else {
  sudbury_fmu_nad83 <- sudbury_fmu
}

# Step 2: Crop to the Sudbury FMU extent
message("✂️ Cropping LandCover to Sudbury extent (fast method)...")
r_sudbury_temp <- terra::crop(r_ca, sudbury_fmu_nad83)

# Step 3: Reproject the cropped raster to EPSG:5070
message("🔄 Reprojecting cropped raster to EPSG:5070 ...")
r_sudbury <- terra::project(r_sudbury_temp, terra::crs(sudbury_fmu))

# Step 4: Apply mask for the Sudbury FMU boundary
message("🎯 Applying mask for Sudbury FMU boundary ...")
r_sudbury <- terra::mask(r_sudbury, sudbury_fmu)

# Step 5: Save clipped output
lcc_clip_path <- file.path(dirs$landcover_ca, "LCC2020v2_Sudbury_30m.tif")
terra::writeRaster(r_sudbury, lcc_clip_path, overwrite = TRUE)

message("✅ Saved clipped LandCover at:\n", lcc_clip_path)

# Display final map
terra::plot(r_sudbury, main = "Sudbury FMU – CEC Land Cover 2020v2 (30m)")
