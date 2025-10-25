############################################################
# studyArea_Sudbury.R – define studyArea functions for Sudbury FMU
# Author: Shirin Varkouhi
# Date: Sys.Date()
############################################################

# ---- Load required packages ----
Require::Require(c("reproducible", "terra", "sf", "LandR"))

# =========================================================
# 1️⃣ Main studyArea (Sudbury FMU boundary + rasterToMatch)
# =========================================================
studyAreaFun <- function() {
  message("⏳ Preparing studyArea for Sudbury FMU ...")
  
  # Load local shapefile
  boundaryFile <- "BOUNDARIES/Sudbury_FMU_5070.shp"
  if (!file.exists(boundaryFile))
    stop("❌ Sudbury FMU shapefile not found: ", boundaryFile)
  
  studyArea <- terra::vect(boundaryFile)
  
  # Create rasterToMatch using LandR LCC 2005
  rasterToMatch <- LandR::prepInputsLCC(
    year = 2005,
    destinationPath = "inputs",
    writeTo = "inputs/rasterToMatch_Sudbury_LCC.tif",
    overwrite = TRUE,
    cropTo = studyArea,
    maskTo = studyArea,
    method = "near",
    fun = "terra::rast"
  )
  
  # Harmonize projections and clean geometry
  studyArea <- terra::project(studyArea, rasterToMatch)
  studyArea <- terra::aggregate(studyArea, dissolve = TRUE)
  terra::writeVector(studyArea, "inputs/studyArea_Sudbury.shp", overwrite = TRUE)
  
  message("✅ Sudbury FMU studyArea created successfully.")
  return(list(rasterToMatch = rasterToMatch, studyArea = studyArea))
}

# =========================================================
# 2️⃣ Large study area (optional)
# =========================================================
studyAreaLargeFun <- function() {
  message("⏳ Preparing large studyArea for Sudbury region ...")
  studyAreaLarge <- terra::buffer(terra::vect("BOUNDARIES/Sudbury_FMU_5070.shp"), width = 50000)
  terra::writeVector(studyAreaLarge, "inputs/studyAreaLarge_Sudbury.shp", overwrite = TRUE)
  message("✅ Large studyArea created.")
  return(studyAreaLarge)
}
