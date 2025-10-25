############################################################
# Global_Sudbury.R – LandR/SpaDES setup for Sudbury FMU
# Author: Shirin Varkouhi
# Version: Final (auto-check + colored messages + test run)
############################################################

# ---- 0️⃣ نصب و بررسی بسته‌ها ----
getOrUpdatePkg <- function(p, minVer, repo) {
  if (!isFALSE(try(packageVersion(p) < minVer, silent = TRUE))) {
    if (missing(repo)) repo = c("predictiveecology.r-universe.dev", getOption("repos"))
    install.packages(p, repos = repo)
  }
}
getOrUpdatePkg("SpaDES.project", "0.0.8.9040")
getOrUpdatePkg("SpaDES.core", "2.1.8")
getOrUpdatePkg("terra", "1.7.78")

library(SpaDES.project)
library(SpaDES.core)
library(crayon)

message(green$bold("\n🌲 شروع راه‌اندازی پروژه LandR برای Sudbury FMU...\n"))
# ---- 🧩 Disable SCANFI download temporarily ----
if ("LandR" %in% loadedNamespaces()) {
  unlockBinding("speciesInStudyArea", asNamespace("LandR"))
  assign("speciesInStudyArea", function(...) {
    message("⚠️ SCANFI download skipped — using empty placeholder raster.")
    return(terra::rast(extent = terra::ext(0,1,0,1), crs = "EPSG:5070"))
  }, envir = asNamespace("LandR"))
  lockBinding("speciesInStudyArea", asNamespace("LandR"))
}

# ---- 1️⃣ تنظیم پروژه ----
out <- SpaDES.project::setupProject(
  updateRprofile = TRUE,
  Restart = TRUE,
  require = c("googledrive", "terra", "sf", "reproducible", "LandR"),
  paths = list(
    projectPath = "E:/MyProjects/ON_Sudbury_LandR",
    modulePath  = file.path("modules"),
    cachePath   = file.path("cache"),
    scratchPath = file.path("scratch"),
    inputPath   = file.path("inputs"),
    outputPath  = file.path("outputs")
  ),
  modules = c(
    "PredictiveEcology/Biomass_speciesData@development",
    "PredictiveEcology/Biomass_borealDataPrep@development",
    "PredictiveEcology/Biomass_speciesParameters@manual",
    "PredictiveEcology/Biomass_core@development",
    "PredictiveEcology/canClimateData@development"
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
      sppEquivCol = "LandR",
      .Plots = "png"
    ),
    Biomass_borealDataPrep = list(overrideAgeInFires = FALSE),
    Biomass_speciesParameters = list(PSPdataTypes = c("NFI", "ON", "NB", "QC"))
  ),
  studyArea = terra::vect("E:/MyProjects/ON_Sudbury_LandR/BOUNDARIES/Sudbury_FMU_5070.shp"),
  rasterToMatch = terra::rast("E:/MyProjects/ON_Sudbury_LandR/LandCover_Canada/LCC2020v2_Sudbury_30m.tif"),
  useGit = TRUE
)

# ---- 2️⃣ بررسی و دانلود ماژول‌ها ----
modules_path <- out$paths$modulePath
dir.create(modules_path, showWarnings = FALSE, recursive = TRUE)

message(blue$bold("\n🔍 بررسی وجود ماژول‌ها در مسیر: "), modules_path)

for (m in out$modules) {
  # بررسی نوع داده
  if (!is.character(m)) {
    message(red("⚠️ هشدار: مقدار ماژول ناشناخته است، در حال رد کردن..."))
    next
  }
  
  # استخراج نام ماژول از مسیر GitHub (فقط نام کوتاه)
  name_only <- sub(".*/", "", sub("@.*", "", m))
  module_folder <- file.path(modules_path, name_only)
  
  if (dir.exists(module_folder) && length(list.files(module_folder)) > 0) {
    message(green(paste0("✅ ماژول ", name_only, " قبلاً وجود دارد.")))
  } else {
    message(yellow(paste0("⬇️ در حال دانلود ماژول ", name_only, " از GitHub ...")))
    tryCatch({
      SpaDES.core::downloadModule(name = name_only, repo = m, path = modules_path, overwrite = TRUE)
      message(green(paste0("✅ ماژول ", name_only, " با موفقیت دانلود شد.")))
    }, error = function(e) {
      message(red(paste0("❌ خطا در دانلود ماژول ", name_only, ": ", e$message)))
    })
  }
}

avail_mods <- basename(list.dirs(out$paths$modulePath, recursive = FALSE))
message(blue$bold("\n📦 ماژول‌های موجود در پروژه:"))
print(avail_mods)


# ---- 3️⃣ ساخت شیء شبیه‌سازی (simList) ----
message(blue$bold("\n⚙️ در حال ساخت شیء شبیه‌سازی (simList)..."))
options("reproducible.useCache" = TRUE)
options("reproducible.inputPaths" = list(
  Biomass_borealDataPrep = "E:/MyProjects/ON_Sudbury_LandR/inputs"
))

test <- SpaDES.core::simInit(
  times = out$times,
  params = out$params,
  modules = out$modules,
  paths = out$paths,
  options = out$options,
  objects = list(
    studyArea = out$studyArea,
    rasterToMatch = out$rasterToMatch
  )
)

# ---- 4️⃣ بررسی ماژول‌های لود شده ----
mods_loaded <- SpaDES.core::modules(test)
if (length(mods_loaded) > 0) {
  message(green$bold("\n✅ ماژول‌ها با موفقیت بارگذاری شدند:"))
  print(mods_loaded)
} else {
  message(red$bold("\n⚠️ هیچ ماژولی بارگذاری نشده — بررسی پارامتر modules در setupProject()."))
}

# ---- 5️⃣ اجرای تست اولیه (۵ event اول) ----
message(yellow$bold("\n🚀 اجرای تست کوتاه (۵ event اول)..."))
tryCatch({
  test_run <- SpaDES.core::spades(test, events = 1:5)
  message(green$bold("\n🎯 تست اولیه با موفقیت انجام شد!"))
}, error = function(e) {
  message(red$bold("\n❌ خطا در اجرای تست اولیه: "), e$message)
})

message(green$bold("\n🌿 Sudbury FMU آماده اجرا و توسعه‌ی مدل‌های LandR است.\n"))
