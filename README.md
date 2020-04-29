
<!-- README.md is generated from README.Rmd. Please edit that file -->

# track2KBA

This package is comprised of functions that facilitate the
identification of areas of importance for biodiversity, such as Key
Biodiversity Areas (KBAs) or Ecologically or Biologically Significant
Areas (EBSAs), based on individual tracking data. For further detail
concerning the method itself, please refer to this
[paper](https://onlinelibrary.wiley.com/doi/full/10.1111/ddi.12411) by
Lacelles et al. (2016).

Key functions include utilities to estimate individual core use areas,
the level of representativeness of the tracked sample, and overlay
individual distributions to identify important aggregation areas. Other
functions assist in formatting your data set, splitting and summarizing
individual foraging trips, and downloading data from
[Movebank](https://www.movebank.org/).

## Installation

You can download the development version from
[GitHub](https://github.com/) with:

``` r
install.packages("devtools", dependencies = TRUE)
devtools::install_github("BirdLifeInternational/track2kba", dependencies=TRUE) # add argument 'build_vignettes = FALSE' to speed it up
```

## Example

Now we will use tracking data collected at a seabird breeding colony to
illustrate a `track2KBA` workflow for identifying important sites. It is
important to note that the specific workflow you use (i.e. which
functions and in what order) will depend on the species of interest and
the associated data at hand.

First, in order for the data to work in track2KBA functions, we can use
the `formatFields` function to format the important data columns needed
for `track2KBA` analysis. These are: a datetime field, latitude and
longitude fields, and an ID field (i.e. individual animal, track, or
trip).

``` r
library(track2KBA) # load package

data(boobies)
# ?boobies  # for some background on the data set 

tracks <- formatFields(boobies, 
  field_ID   = "track_id", 
  field_Date = "date_gmt", 
  field_Time = "time_gmt",
  field_Lon  = "longitude", 
  field_Lat  = "latitude"
  )
```

If your data come from a central-place foraging species (i.e. one which
makes trips out from a centrally-located place, such as a nest in the
case of a bird), you can use `tripSplit` to split up the data into
discrete trips.

In order to do this, you must identify the location of the central place
(e.g. nest or colony).

``` r
library(dplyr)

# here we know that the first points in the data set are from the nest site
colony <- tracks %>% 
  summarise(
    Longitude = first(Longitude), 
    Latitude  = first(Latitude))
```

Our *colony* dataframe tells us where trips originate from. Then we need
to set some parameters to decide what constitutes a trip. To do that we
should use our understanding of the movement ecology of the study
species. So in this case we know our seabird travels out to sea on the
scale of a few kilometers, so we set *InnerBuff* (the minimum distance
from the colony) to 3 km, and *Duration* (minimum trip duration) to 1
hour. *ReturnBuff* can be set further out in order to catch incomplete
trips, where the animal began returning, but perhaps due to device
failure the full trip wasn’t captured.

Optionally, we can set *rmNonTrip* to TRUE which will remove the periods
when the birds were not on trips.

``` r
trips <- tripSplit(
  tracks     = tracks, 
  Colony     = colony, 
  InnerBuff  = 3,      # kilometers
  ReturnBuff = 10, 
  Duration   = 1,      # hours
  plot     = TRUE,   # visualize individual trips
  rmNonTrip  = TRUE)
```

<img src="man/figures/README-unnamed-chunk-3-1.png" width="80%" height="80%" style="display: block; margin: auto;" />

Then we can summarize the trip movements, using `tripSummary`. First, I
will filter out data from trips that did not return to the vicinity of
the colony (i.e. within ReturnBuff), so they don’t skew the estimates.

``` r
trips <- subset(trips, trips$Returns == "Yes" )

tripSum <- tripSummary(Trips = trips, Colony = colony)

tripSum
```

Now that we have an idea how the animals are moving, we can start with
the process of estimating their space use areas, and sites of
aggregation\!

`findScale` provides options for setting the all-important smoothing
parameter in the Kernel Density Estimation. It calculates candidate
smoothing parameters using several different methods.

If we know our animal uses an area-restricted search (ARS) strategy to
locate prey, then we can set the `ARSscale=TRUE`. This uses First
Passage Time analysis to identify the spatial scale at which
area-restricted search is occuring, which may then be used as the
smoothing parameter value.

``` r
Hvals <- findScale(trips,
  ARSscale      = TRUE,
  Trip_summary = tripSum)

Hvals
```

The other values are more simplistic methods of calculating the
smoothing parameter. `href` is the canonical method, and relates to the
number of points in the data and their spatial variance. `mag` and
`scaled_mag` are based on the average foraging range (`med_max_dist` in
the *tripSum* output) estimated from the trips present in the data.
These two methods only work for central-place foragers.

Then, we must select a smoothing parameter value. To inform our
decision, we ought to use our understanding of the species’ movement and
foraging ecology to guide our decision about what scales make sense.
That is, from the `findScale` output, we want to exclude values which we
believe may under- or over-represent the area used by the animals while
foraging.

Once we have chosen a smoothing value, we can produce Kernel Density
Estimations for each individual, using `estSpaceUse`. By default this
function isolates each animal’s core range (i.e. the 50% utilization
distribution, or where the animal spends about half of its time) which
is a commonly used standard (Lascelles et al. 2016). However, this can
easily be adjusted using the `UDLev` argument.

Note: here we might want to remove the trip start and end points that
fall within the InnerBuff we set in TripSplit, so that they don’t skew
the at-sea distribution towards to colony.

``` r
trips <- trips[trips$ColDist > 3, ] # remove trip start and end points near colony

KDEs <- estSpaceUse(
  DataGroup = trips, 
  Scale = Hvals$mag, 
  UDLev = 50, 
  polyOut = TRUE,
  plot  = TRUE
  )
```

<img src="man/figures/README-estSpaceUse-1.png" width="80%" height="80%" style="display: block; margin: auto;" />
At this step we should verify that the smoothing parameter value we
selected is producing reasonable space use estimates, given what we know
about our study animals. Are the core areas much larger than expected?
Much smaller? If so, consider using a different value for the `Scale`
parameter.

The next step is to estimate how representative this sample of animals
is of the population. That is, how well does the variation in space use
of these tracked individuals encapsulate variation in the wider
population? To do this, we use the `repAssess` function. This function
repeatedly samples a subset of individual core ranges, averages them
together, and quantifies how many points from the unselected individuals
fall within this combined core range area. This process is run across
the range of the sample size, and iterated a chosen number of times.

To speed up this procedure, we can supply the output of `estSpaceUse`.
We can choose the number of times we want to re-sample at each sample
size by setting the `Iteration` argument. The higher the number the more
confident we can be in the results, but the longer it will take to
compute.

``` r
repr <- repAssess(trips, KDE = KDEs$KDE.Surface, Iteration = 50, BootTable = FALSE)
```

The output is a dataframe, with the estimated percentage of
representativeness given in the `out` column.

The relationship between sample size and the percent coverage of
un-tested animals’ space use areas (i.e. *Inclusion*) is visualized in
the output plot seen below, which is automatically saved to the working
directoty (i.e. `getwd()`) each time `repAssess` is run.

By quantifying this relationship, we can estimate how close we are to an
information asymptote. Put another way, we have estimated how much new
space use information would be added by tracking more animals. In the
case of this seabird dataset, we estimate that \~98% of the core areas
used by this population are captured by the sample of 39 individuals.
Highly representative\!

<img src="man/figures/README-repAssess-1.png" width="80%" height="80%" style="display: block; margin: auto;" />

Now, using `findKBA` we can identify aggregation areas. Using the core
area estimates of each individual we can calculate where they overlap.
Then, we estimate the proportion of the larger population in a given
area by adjusting our overlap estimate based on the degree of
representativeness we’ve achieved.

Here, if we have population size estimates, we can include this value
(using the `popSize` argument) to estimate to output a number of
individuals aggregating in space, which can then use to compare against
importance criteria (i.e KBA, EBSA criteria). If we don’t this will
output a percentage of individuals instead.

If you desire polygon output of the overlap areas, instead of a gridded
surface, you can indicate this using the `polyOut` argument. This
aggregates all cells with the same estimated number/percentage of
individuals into to single polygons.

``` r
KBAs <- findKBA(
  KDE = KDEs,
  Represent = repr$out,
  UDLev = 50,
  popSize = 500,     # 500 seabirds breed one the island
  polyOut = TRUE,
  plot = FALSE)     # we will plot in next step

class(KBAs)
```

In `findKBA` we can specify `plot=TRUE` if we want to visualize the
result right away. However, there a numerous ways in which we might want
to customize the output. The following are examples of code which can be
used to visualize the two types of output from the `findKBA` function.

If we specified `polyOut=TRUE`, then the output will be in Simple
Features format, and the data are spatial polygons. This allows us to
easily take advantage of the `ggplot2` plotting syntax to make an
attractive map\!

``` r
coordsets <- sf::st_bbox(KBAs)

KBAPLOT <- KBAs %>% dplyr::filter(.data$potentialKBA==TRUE) %>%
  ggplot() +
  geom_sf(mapping = aes(fill=N_animals, colour=N_animals)) +  # if not exporting to pdf, colour="transparent" works
  borders("world", fill="dark grey", colour="grey20") +       # plot basic land mass dataset from maps package
  coord_sf(
    xlim = c(coordsets$xmin, coordsets$xmax),
    ylim = c(coordsets$ymin, coordsets$ymax), expand = FALSE) +
  theme(panel.background=element_blank(),
    panel.grid.major=element_line(colour="transparent"),
    panel.grid.minor=element_line(colour="transparent"),
    axis.text=element_text(size=14, colour="black"),
    axis.title=element_text(size=14),
    panel.border = element_rect(colour = "black", fill=NA, size=1)) +
  guides(colour=FALSE) +
  scale_fill_continuous(name = "N animals") +
  ylab("Latitude") +
  xlab("Longitude")

## we can easily add the colony location information for reference
KBAPLOT <- geom_point(data=colony, aes(x=Longitude, y=Latitude), col='red', shape=16, size=2)

## in case you want to save the plot
# ggplot2::ggsave("KBAPLOT", device="pdf")
```

<img src="man/figures/KBA_sf_plot.png" width="70%" height="70%" />

This map shows the ‘potential KBA’ area; that is, the areas which are
used by a significant proportion of the local population, given the
representativeness of the sample of tracked individuals. In this case,
since representativeness is \>90%, any area used by 10% or more of the
population is considered important (see Lascelles et al. 2016 for
details).

Then, we can combine all the polygons within the ‘potentialKBA’ area,
and using the maximum number of individuals present in that area we can
assess whether it merits designation as a Key Biodiversity Area
according to the KBA standard.

``` r
potKBA <- KBAs %>% dplyr::filter(.data$potentialKBA==TRUE) %>% 
   summarise(
     max_animals = max(na.omit(N_animals)), # maximum number of animals aggregating in the site
     min_animals = min(na.omit(N_animals))  # minimum number using the site
   )

# plot(potKBA[1])
```

\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~

If in `findKBA` we instead specify `polyOut=FALSE`, our output will be a
spatial grid of animal densities, with each cell representing the
estimated number, or percentage of animals using that area. So this
output is irrespective of the representativness-based importance
threshold.

``` r

plot(KBA_sp[KBA_sp$N_animals > 0, ])
```

<img src="man/figures/KBA_sp_plot.png" width="70%" height="70%" />

This plot shows the minimum estimated number of birds using the space
around the breeding island.
