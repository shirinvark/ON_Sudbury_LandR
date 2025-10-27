############################################################
# Global_Sudbury.R – LandR/SpaDES setup for Sudbury FMU
# Author: Shirin Varkouhi
# Date: Sys.Date()
############################################################

# ---- 0️⃣ Install or update packages ----
getOrUpdatePkg <- function(p, minVer, repo) {
  if (!isFALSE(try(packageVersion(p) < minVer, silent = TRUE))) {
    if (missing(repo)) repo = c("predictiveecology.r-universe.dev", getOption("repos"))
    install.packages(p, repos = repo)
  }
}
getOrUpdatePkg("SpaDES.project", "0.0.8.9040")

library(SpaDES.project)
# ---- 🚫 Force-disable SCANFI inside LandR (even after reload by SpaDES) ----
setHook(packageEvent("LandR", "onLoad"), function(...) {
  try({
    unlockBinding("prepSpeciesLayers_SCANFI", asNamespace("LandR"))
    assign("prepSpeciesLayers_SCANFI", function(...) {
      message("⚠️ SCANFI fully disabled — returning dummy raster.")
      return(terra::rast(terra::ext(0, 1, 0, 1), ncol = 1, nrow = 1, vals = NA))
    }, envir = asNamespace("LandR"))
    lockBinding("prepSpeciesLayers_SCANFI", asNamespace("LandR"))
  }, silent = TRUE)
})

# ---- 🧩 Optional LandR options (disable SCANFI temporarily) ----
options(
  LandR.useSCANFI = FALSE,         
  LandR.tryLoadingSCANFI = FALSE   
)

# ---- 1️⃣ Setup the project ----
out <- SpaDES.project::setupProject(
  updateRprofile = TRUE,
  Restart = TRUE,
  require = c("googledrive", "terra", "sf", "reproducible", "LandR"),
  paths = list(
    projectPath = "E:/MyProjects/ON_Sudbury_LandR",
    modulePath = file.path("modules"),
    cachePath = file.path("cache"),
    scratchPath = file.path("scratch"),
    inputPath = file.path("inputs"),
    outputPath = file.path("outputs")
  ),
  modules = c(
    "PredictiveEcology/Biomass_speciesData@development",
    "PredictiveEcology/Biomass_borealDataPrep@development",
    "PredictiveEcology/Biomass_speciesParameters@manual",
    "PredictiveEcology/Biomass_core@development",
    "PredictiveEcology/canClimateData@development"
    #  gmcsDataPrep  
  ),
  options = list(
    spades.allowInitDuringSimInit = TRUE,
    LandR.assertions = FALSE,
    reproducible.objSize = FALSE,
    reproducible.useCache = "overwrite",
    reproducible.shapefileRead = "terra::vect",
    spades.recoveryMode = 1,
    spades.moduleCodeChecks = FALSE
  ),
  times = list(start = 2010, end = 2051),
  
  params = list(
    .globals = list(
      .studyAreaName = "Sudbury_FMU",
      dataYear = 2010,
      sppEquivCol = 'LandR',
      .Plots = "png",
      LandR.useSCANFI = FALSE,        
      LandR.tryLoadingSCANFI = FALSE  
    ),
    Biomass_speciesData = list(
      useSCANFI = FALSE,              
      tryLoadingSCANFI = FALSE
    ),
    Biomass_borealDataPrep = list(overrideAgeInFires = FALSE),
    Biomass_speciesParameters = list(PSPdataTypes = c("NFI","ON","NB","QC"))
  ),
  
  # ---- 2️⃣ Custom spatial inputs ----
  studyArea = terra::vect("E:/MyProjects/ON_Sudbury_LandR/BOUNDARIES/Sudbury_FMU_5070.shp"),
  rasterToMatch = terra::rast("E:/MyProjects/ON_Sudbury_LandR/LandCover_Canada/LCC2020v2_Sudbury_30m.tif"),
  
  useGit = TRUE
)

# ---- 3️⃣ Climate & model variables ----
historical_prd <- c("1951_1980", "1981_2010")
historical_yrs <- c("1991_2022")
projected_yrs <- c(2011:2051)

out$climateVariables <- list(
  historical_CMI_normal = list(
    vars = "historical_CMI_normal",
    fun = quote(calcCMInormal),
    .dots = list(historical_period = historical_prd, historical_years = historical_yrs)
  ),
  projected_ATA = list(
    vars = c("future_MAT", "historical_MAT_normal"),
    fun = quote(calcATA),
    .dots = list(historical_period = historical_prd, future_years = projected_yrs)
  ),
  projected_CMI = list(
    vars = "future_CMI",
    fun = quote(calcAsIs),
    .dots = list(future_years = projected_yrs)
  )
)

# ---- 4️⃣ Run the simulation ----
test <- do.call(SpaDES.core::simInitAndSpades, out)

message("✅ Sudbury FMU simulation initialized successfully.")
