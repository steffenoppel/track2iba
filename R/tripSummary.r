## tripSummary   ###############################################################

#' Summary of trip movements
#'
#' \code{tripSummary} provides a simple summary of foraging trip distances, 
#' durations, and directions performed by central place foraging animals.
#'
#' \emph{nests}=T may be used if it is desired, for example, to use specific 
#' nest locations instead of one central location for all individuals/tracks.
#'
#' @param trips SpatialPointsDataFrame, as produced by \code{\link{tripSplit}}.
#' @param colony data.frame with 'Latitude' and 'Longitude' columns specifying 
#' the locations of the central place (e.g. breeding colony). If nests=TRUE, 
#' \code{colony} should have a third column, 'ID' with corresponding character 
#' values in the 'ID' field in \emph{trips}.
#' @param nests logical scalar (TRUE/FALSE). Were central place 
#' (e.g. deployment) locations used in \code{tripSplit} specific to each unique
#'  'ID'? If so, each place must be matched with an 'ID' value in both 
#'  \emph{trips} and \emph{colony} objects.
#'
#' @return Returns a tibble data.frame grouped by ID. Trip characteristics 
#' included are trip duration (in hours), maximum distance and cumulative 
#' distance travelled (in kilometers), direction (in degrees, measured from 
#' origin to furthest point of track), start and end times as well as a unique 
#' trip identifier ('tripID') for each trip performed by each individual in the
#'  data set. Distances are calculated on a great circle.
#' 
#' If the beginning of a track is starts out on a trip which is followed by only
#'  one point within \emph{InnerBuff}, this is considered an 'incomplete' trip 
#'  and will have an NA for duration. If an animal leaves on a trip but does not
#'  return within the \emph{ReturnBuff} this will be also classified an 
#'  'incomplete trip'. 
#'
#' @seealso \code{\link{tripSplit}}
#'
#' @export
#' @import dplyr
#'

tripSummary <- function(trips, colony=NULL, nests=FALSE)
  {

  if(!"Latitude" %in% names(colony)) stop("colony missing Latitude field")
  if(!"Longitude" %in% names(colony)) stop("colony missing Longitude field")

  ### helper function to calculate distance unless no previous location -------
  poss_dist <- purrr::possibly(geosphere::distm, otherwise = NA)

  if(class(trips) == "SpatialPointsDataFrame"){
    trips <- as.data.frame(trips@data)
  } else { trips <- trips }
  
  ## summaries ----------------------------------------------------------------
  trip_distances <- trips %>%
    tidyr::nest(coords=c(.data$Longitude, .data$Latitude)) %>%
    group_by(.data$tripID) %>%
    mutate(prev_coords = dplyr::lag(.data$coords)) %>%
    ungroup() %>%
    mutate(Dist = purrr::map2_dbl(
      .data$coords, .data$prev_coords, poss_dist)
      ) %>%
    mutate(Dist = if_else(is.na(.data$Dist), .data$ColDist, .data$Dist)) %>%
    mutate(count=1) %>%
    group_by(.data$ID, .data$tripID) %>%
    summarise(n_locs = sum(.data$count),
              departure = min(.data$DateTime),
              return = max(.data$DateTime),
              duration = ifelse( "No" %in% unique(.data$Returns), NA,
                as.numeric(
                   difftime(max(.data$DateTime) - min(.data$DateTime), "hours")
                   )
                ),
              total_dist = sum(.data$Dist, na.rm = TRUE)/1000,
              max_dist = max(.data$ColDist)/1000) %>%
    mutate(
      direction= 0,
      duration = ifelse(.data$duration==0, NA, .data$duration),
      complete = ifelse(
        is.na(.data$duration), "incomplete trip","complete trip"
        )
      ) 
  
  ### LOOP OVER EACH TRIP TO CALCULATE DIRECTION TO FURTHEST POINT FROM COLONY 
  for (i in unique(trip_distances$tripID)){
    x <- trips@data[trips@data$tripID==i,]
    maxdist <- cbind(
      x$Longitude[x$ColDist==max(x$ColDist)],
      x$Latitude[x$ColDist==max(x$ColDist)]
      )
    if(dim(maxdist)[1] > 1){maxdist <- maxdist[1, ]}

    if(nests == TRUE) {origin <- colony[match(unique(x$ID), colony$ID),] %>% 
      dplyr::select(.data$Longitude, .data$Latitude)} else {origin <- colony}
    
    ## great circle (ellipsoidal) bearing of trip -----------------------------
    b <- geosphere::bearing( c(origin$Longitude,origin$Latitude), maxdist)	
    ## convert the azimuthal bearing to a compass direction -------------------
    trip_distances$direction[trip_distances$tripID==i] <- (b + 360) %% 360 
  }
if("incomplete trip" %in% trip_distances$complete) warning(
  "Some trips did not return to the specified returnBuffer distance from the 
  colony. The return DateTime given for these trips refers to the last location 
  of the trip, and NOT the actual return time to the colony.")
  
return(trip_distances)
}
