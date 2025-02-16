## METADATA ===============================================================
## Description: Get distance stats across sites from different classes
## and integrate thought time.
## # CELL MOVEMENT ANALYSIS
## # This script loads the EastAfrica climate classification data,
## # extracts the classification for every time step,
## # and then, for each cell, computes the distance it would have to “move”
## # at each subsequent time step in order to be in a cell that still
## # shows its original (first time) climate class. 
##
## R version: 4.2.2 for Windows
## Date: 2025-02-07 14:25:35
## License: GPL3
## Author: Oskar Hagen (oskar@hagen.bio)
##=======================================================================##
### DATA PREPARATION

# Install necessary packages if they are not already installed
if (!require("rstudioapi")) install.packages("rstudioapi")
if (!require("tiff")) install.packages("tiff")
if (!require("terra")) install.packages("terra")
if (!require("sf")) install.packages("sf")
if (!require("rnaturalearthdata")) install.packages("rnaturalearthdata")
if (!require("RANN")) install.packages("RANN")  # for fast nearest neighbor search

# Load packages
## library(rstudioapi)
library(tiff)
library(terra)
library(sf)
library(rnaturalearthdata)
library(RANN)
source("support_functions.R")
# Set the working directory to the directory where this script is located
# setwd(dirname(getActiveDocumentContext()$path))
# (Assume that your data are in the subfolder "data")
#setwd("data")

# Print current working directory
#print(getwd())

setwd("C:/Users/am92guke/My Documents/iDiv/Sec_papers/MAPAS_eastafrica_Marta/data")


# Load the raster file (the Köppen–Geiger reclassification of East Africa)
# (The file is assumed to be one multi‐layer .tif where each layer is a time slice)
EastAfrica_path <- file.path("..", "data", "EastAfrica_2_5My.tif")
image_EastAfrica <- rast(EastAfrica_path)

# (Optional) Load shapefiles for plotting (as in your original script)
ocean            <- read_sf("ne_110m_ocean.shp")
countries        <- read_sf("ne_110m_admin_0_countries.shp")
countries_filler <- read_sf("ne_110m_land.shp")
rivers           <- read_sf("ne_10m_rivers_lake_centerlines.shp")
lakes            <- read_sf("ne_10m_lakes.shp")

#####################################
# EXTRACT THE CLASSIFICATION MATRIX
#####################################

# Get the number of layers (time steps) and cells (pixels)
n_time  <- nlyr(image_EastAfrica)
n_cells <- ncell(image_EastAfrica)

# Create a matrix to store the classification for each time step.
# Rows = time slices; Columns = cells.
# (Each cell will have a value 1, 2 or 3 corresponding to the climate classes,
# as in your original classification.)
res <- matrix(NA, nrow = n_time, ncol = n_cells)

# Loop over time slices and store the cell values
pb <- txtProgressBar(min = 1, max = n_time, style = 3)
for (i in 1:n_time) {
  # add progress based on time
  setTxtProgressBar(pb, i)
  res[i, ] <- as.vector(image_EastAfrica[[i]])
}
close(pb)

# # plot a specific time step taking res as input, colour the different cathegories
# t_time <- 1843 
# plot(image_EastAfrica[[t_time]], main=t_time, col = c("red", "green", "blue"), legend = FALSE)

# (For reference, you might want to save or inspect "res" or a summary of it)
cat("Dimensions of classification matrix (time x cells):", dim(res), "\n")


#####################################
# PREPARE CELL COORDINATES
#####################################

# Get the spatial (x,y) coordinates for each cell.
# The function 'xyFromCell' returns a matrix with columns "x" and "y"
cell_coords <- xyFromCell(image_EastAfrica, 1:n_cells)

#####################################
# COMPUTE MOVEMENT DISTANCES
#####################################

# We now define the reference classification as the first time step.
initial_class <- res[1, ]
# define class to study here!
cl <- 3
initial_class[initial_class[]!=cl] <- NA


# stat loop over all classes here
# For each class, we will compute the distance to the nearest cell of the same class
# at each subsequent time step.
the_types <- names(table(res))
n_types <- length(the_types)

# create dummy per type, a list with sublist with same name as types
l_types <- vector("list", length = n_types)
names(l_types) <- the_types

# Create a list to store, for each time step, a vector of movement distances.
# For time step 1, no cell “moves” (distance = 0).
# movement_list <- vector("list", length = n_time)
# movement_list[[1]] <- rep(0, n_cells)
dummy_list <- lapply(1:(n_time-1), function(x) {
  list()
  #list("ALL"=NA, "N"=NA, "S"=NA)
})
# dummy_all_list <- lapply(1:(n_time-1), function(x) {
#   list()
# })
l_summary <- list("extinct"=dummy_list, "new"=dummy_list)
summary <- list("extinct"=rep(NA, n_time-1), "new"=rep(NA, n_time-1))


#### split North and South
# Create a SpatRaster with 80 rows, 80 columns,
# extent: xmin=20, xmax=60, ymin=-20, ymax=20, resolution=0.5
r <- image_EastAfrica[[1]]
r[] <- 0
# plot(r, main = "Empty Raster with Defined Extent")

points <- cbind(c(20, 60), c(20, -20))
print(points)
# Get the coordinates (cell centers) for all cells in the raster.
xy_coords <- xyFromCell(r, 1:ncell(r))
# xy_coords is a matrix with two columns: the x and y coordinates of each cell center.

# Compute the expected y value on the line for each x coordinate:
line_y <- -xy_coords[,1] + 40

# Create a mask for cells above the line: cell center y > line_y.
mask_above_values <- ifelse(xy_coords[,2] > line_y, 1, NA)
mask_above <- setValues(r, mask_above_values)

# Create a mask for cells below the line: cell center y < line_y.
mask_below_values <- ifelse(xy_coords[,2] < line_y, 1, NA)
mask_below <- setValues(r, mask_below_values)


NS_dummy <- list("ALL"=list(),"N"=list(),"S"=list())
NS_dummy_vector <- list("ALL", "N"=NA, "S"=NA)

# For each subsequent time step, compute for every cell:
# - If the cell still has its original (initial) class, distance = 0.
# - Otherwise, find the nearest cell (at that time step) that has the same class
#   as the cell’s initial class, and record the distance.
# We use the RANN::nn2 function to perform fast nearest-neighbor searches.
for (t in 2:n_time) {#5){#  ### ALLAWYS START ON 2 or more, never on 1
  current_class <- res[t, ]
  previous_class <- res[t-1, ]
  
  #movement      <- numeric(n_cells)  # will store distances for time step t
  
  current_class[current_class[]!=cl] <- NA
  current_class[current_class == "NaN"] <- NA
  # current_class[is.na(current_class)] <- 0
  
  previous_class[previous_class[]!=cl] <- NA
  previous_class[previous_class == "NaN"] <- NA
  # previous_class[is.na(previous_class)] <- 0
  
  # initial_class[initial_class[]!=cl] <- NA
  # For cells that already have their original class, no movement is needed.
  same_idx <- which(current_class == previous_class)
  # print(current_class[same_idx])
  # movement[same_idx] <- 0
  
  current_class_zero <- current_class
  current_class_zero[is.na(current_class)] <- 0
  previous_class_zero <- previous_class
  previous_class_zero[is.na(previous_class)] <- 0
  
  # For cells that have lost their original class:
  diff_idx <- which(previous_class_zero != current_class_zero)
  # get direction of change, if FALSE, i.e. negative, there was removal of cell
  # if true or positive, there was an increment of suitable cell
  diff_idx_dir <- current_class_zero - previous_class_zero
  diff_idx_dir[diff_idx_dir == 0] <- NA
  diff_idx_dir[diff_idx_dir > 0] <- 1
  diff_idx_dir[diff_idx_dir < 0] <- 0
  
 
  # plot current time
  reff <- image_EastAfrica[[t]]
  plot(reff, main=t, col = c( NA,NA, "green"), legend = FALSE)
  reff_diff <- reff
  values(reff_diff) <- diff_idx_dir
  plot(reff_diff, main=t, col=c("red", "blue"), legend = FALSE, add = TRUE)
  usr <- par("usr")
  legend(x = usr[2]-22, y = usr[4]-0,
         legend = c("unchanged", "extinct", "new"), 
         fill = c("green", "red", "blue"), 
         title = "Categories", 
         bty = "n",      # no box around the legend
         cex = 0.7)  
# end plot
  
  


  ### WIP
for (pos_i in c(names(NS_dummy))){
  diff_idx_dir_r <- mask_above
  diff_idx_dir_r[] <- diff_idx_dir
  if (pos_i=="N"){
    mask_i <- mask_above
  } else if (pos_i=="S"){
    mask_i <- mask_below
  } else if (pos_i=="ALL"){
    mask_i <- 1
  } else {
    stop("name has to be either N or N")
  }
  ### END WIP
  if(sum(!is.na(diff_idx_dir)) > 0){
        # It is efficient to process by the desired (original) class.
    # for (cl in unique(initial_class[diff_idx])) {
      # For this class, identify the cells (among those that changed)
      # whose original classification is cl.
  target_idx <- which((diff_idx_dir*mask_i[])==0)
      #target_idx <- which(previous_class[diff_idx_dir] == cl)
      #target_idx <- diff_idx[ previous_class[diff_idx] == cl ]
      
      # In the current time step, find all cells that are of class cl.
      candidate_idx <- which(current_class == cl)
      
      if (length(candidate_idx) > 0 & length(target_idx) > 0) {
        # Use the RANN package to find, for each target cell,
        # the distance to the nearest candidate cell.
        # nn2 returns a list with elements "nn.idx" and "nn.dists".
        nn_res <- nn2(data = cell_coords[candidate_idx, , drop = FALSE],
                      query = cell_coords[target_idx, , drop = FALSE],
                      k = 1)
        
        l_summary$extinct[[t-1]] <- c(nn_res$nn.dists)
        summary$extinct[t-1] <- mean(nn_res$nn.dists)
        
        #show movements
        arrows(cell_coords[target_idx, 1], cell_coords[target_idx, 2],
               cell_coords[candidate_idx[nn_res$nn.idx], 1],
               cell_coords[candidate_idx[nn_res$nn.idx], 2],
               col = "black", length = 0.1)
        
        #movement[target_idx] <- nn_res$nn.dists[,1]
      } else {
        l_summary$extinct[[t-1]] <- 0
        summary$extinct[t-1] <- 0
        # If no candidate cell of the desired class exists, record NA.
        #movement[target_idx] <- NA
      }
    #} # end for each unique desired class
  }
  # Store the movement distances for time step t in the list.
  # movement_list[[t]] <- movement
    else {
  l_summary$extinct[[t-1]] <- 0
  summary$extinct[t-1] <- 0
} 
  
  # (Optional) Print progress every 10 time steps.
  if(t %% 10 == 0) cat("Processed time step:", t, "of", n_time, "\n")

  # end for each time step
  NS_dummy[[pos_i]]$extinct[[t-1]] <- l_summary$extinct[[t-1]]
  #NS_dummy_vector[[pos_i]]$extinct <- summary
} # end for each position
} # end for each time step
#####################################
# SAVE OR ANALYZE THE MOVEMENT DATA
#####################################

saveRDS(NS_dummy, file = "../results/cell_movement_distances.rds")
saveRDS(NS_dummy_vector, file = "../results/cell_movement_distances_vector.rds")


# read rds
NS_dummy <- readRDS("../results/cell_movement_distances.rds")


dummy_list_stats <- list("ALL"=list(), "N"=list(), "S"=list())
stats <- list("extinct"=dummy_list_stats, "new"=dummy_list_stats)

for (group_i in names(NS_dummy)){
  stats$extinct[[group_i]] <- compute_stats(data=NS_dummy, group=group_i, type="extinct")
  #stats$new[[group_i]] <- compute_stats(data=NS_dummy, group=group_i, type="new")
  #print(extinct_stats)
}

saveRDS(stats, file = "../results/cell_movement_distances_stats.rds")

par(mfrow = c(3, 1))
# plot all stats for N and S
for (group_i in 1:length(names(NS_dummy))){
  group_name_i <- names(NS_dummy)[group_i]
  group_color <- c("black", "yellow", "darkgreen")[group_i]
  # empty plot
  #plot(1, type = "n", xlab = "", ylab = "", xlim = c(0, n_time-1), ylim = c(0, 1))
  plot(stats$extinct[[group_name_i]][, c("timeStep", "sum")], main=group_name_i, type="l", col=group_color, lwd=1, xlab="kyrs", ylab="Sum movement distance")

}




# new plot

par(mfrow = c(3, 1), mar = c(2, 4, 2, 1), oma = c(4, 0, 0, 0))  # Adjust margins

# plot all stats for N and S
for (group_i in 1:length(names(NS_dummy))) {
  group_name_i <- names(NS_dummy)[group_i]
  group_color <- c("magenta", "blue", "red")[group_i]
  
  # Determine x-axis label conditionally
  xlab_value <- ifelse(group_i == length(names(NS_dummy)), "kyrs", "")
  
  # Plot the data
  plot(stats$extinct[[group_name_i]][, c("timeStep", "mean")], 
       main = group_name_i, type = "l", col = group_color, 
       lwd = 1, xlab = xlab_value, ylab = "Mean movement distance", xaxt = ifelse(group_i == length(names(NS_dummy)), "s", "n"))
}


plot(stats$extinct[["S"]][, c( "sum")]-stats$extinct[["N"]][, c("sum")], type="l", main="S-N", ylab="diff S-N sum movement", xlab="years ago")




plot(stats$extinct[["S"]][, c( "mean")]-stats$extinct[["N"]][, c("mean")], type="l", main="S-N", ylab="diff S-N mean movement", xlab="years ago")
abline(h=0, col="red")


# print(extinct_stats_ALL)

# plot as lines extinct_stats_ALL, from present to the past, i.e. mean, sum and area
plotlines <- function(plotdata, title){
  par(mfrow = c(1, 3))
  plot(plotdata$timeStep, plotdata$mean, type = "l", col = "blue", lwd = 2,
       xlab = "Time step", ylab = "Mean movement distance",
       main = "Mean Movement Distance vs Time")
  plot(plotdata$timeStep, plotdata$area, type = "l", col = "black", lwd = 2,
       xlab = "Time step", ylab = "Area movement distance",
       main = "Area Movement Distance vs Time")  
  plot(plotdata$timeStep, plotdata$sum, type = "l", col = "red", lwd = 2,
       xlab = "Time step", ylab = "Sum movement distance",
       main = "Sum Movement Distance vs Time")
}
plotlines(plotdata=extinct_stats_ALL, "ALL")

mean_movement_extinct <- NS_dummy_vector$ALL$extinct
sum_movement_extinct <- lapply(NS_dummy_vector$ALL$extinct, sum)
area_movement_extinct <- unlist(lapply(NS_dummy$ALL$extinct, length))

### WIP
# plot movement mean, sum and area across time
par(mfrow = c(1, 3))
plot(1:(n_time-1), mean_movement_extinct, type = "l", col = "blue", lwd = 2,
     xlab = "Time step", ylab = "Mean movement distance",
     main = "Mean Movement Distance vs Time")
plot(1:(n_time-1), sum_movement_extinct, type = "l", col = "red", lwd = 2,
     xlab = "Time step", ylab = "Sum movement distance",
     main = "Sum Movement Distance vs Time")
     #, add=T)
plot(1:(n_time-1), area_movement_extinct, type = "l", col = "blue", lwd = 2,
     xlab = "Time step", ylab = "Area movement distance",
     main = "Area Movement Distance vs Time")

# make same as before but in one plot


# For example, you can combine the movement data into a matrix
# with rows = time steps and columns = cells.
movement_mat <- do.call(rbind, NS_dummy_vector)

# You might then save the matrix to a CSV file:
write.csv(movement_mat, file = "../results/cell_movement_distances.csv", row.names = FALSE)

# Alternatively, you might want to compute summary statistics per time step.
# For instance, the mean (or median) movement distance (ignoring NAs):
mean_movement <- sapply(movement_list, function(x) mean(x, na.rm = TRUE))
median_movement <- sapply(movement_list, function(x) median(x, na.rm = TRUE))

# Plot the temporal evolution of the average movement distance
time_axis <- 1:n_time  # or convert to "million years before present" as needed

par(mfrow = c(1, 2))
plot(time_axis, mean_movement, type = "l", col = "blue", lwd = 2,
     xlab = "Time step", ylab = "Mean movement distance",
     main = "Mean Movement Distance vs Time")
plot(time_axis, median_movement, type = "l", col = "red", lwd = 2,
     xlab = "Time step", ylab = "Median movement distance",
     main = "Median Movement Distance vs Time")

# (Optional) You can also look at the movement distances for a given cell or a set of cells.

#####################################
# END OF SCRIPT
#####################################

