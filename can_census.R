library(tidyverse)
library(sf)
library(rjson)
library(cancensus)
library(leaflet)
library(leafsync)

# Read Data ----

# > set up cancensus api key
json_data <- fromJSON(file='secret.json')
options(cancensus.api_key = json_data[["CensusMapper_API_key"]])

# > set up cancensus cache_path 
options(cancensus.cache_path = file.path(getwd(), '_cache_cancensus'))

## Census data
# define census year and spatial level of aggregation
dataset='CA16'
level="DA"
# INFO - level by dissemination area 
# one or more adjacent dissemination blocks with an average population of 400 to 700 persons 
# based on data from the previous Census of Population Program. 
# It is the smallest standard geographic area for which all census data are disseminated.

# > list of all regions
all_regions <- list_census_regions(dataset)
#select GVRD for analysis
regions <- all_regions %>%
  filter(level==level) %>% 
  filter(CD_UID %in% c(5915)) %>% # Metro Van
  as_census_region_list

# > list of all vectors
all_vectors <- list_census_vectors(dataset)

# # > find variables
# all_vectors %>%
#   filter(grepl("income",label)) %>%
#   # filter(vector == 'v_CA16_406') %>%
#   View

# > variable list
# v_CA16_4895	Total	Median value of dwellings ($)
# v_CA16_4893	Total	Median monthly shelter costs for owned dwellings ($)
# v_CA16_4900	Total	Median monthly shelter costs for rented dwellings ($)
#
# v_CA16_2397	Total	Median total income of households in 2015 ($)
# v_CA16_2207	Total	Median total income in 2015 among recipients ($)
# v_CA16_2213	Total	Median after-tax income in 2015 among recipients ($)
# v_CA16_2219	Total	Median market income in 2015 among recipients ($)
# 
# v_CA16_401	Total	Population, 2016
# v_CA16_407	Total	Land area in square kilometres
# v_CA16_406	Total	Population density per square kilometre
# v_CA16_379	Total	Average age
# v_CA16_425	Total	Average household size
# v_CA16_2449	Total	Average family size of economic families
# v_CA16_5603	Total	Employed
# v_CA16_5651	Total	Self-employed

# set vectors
vectors <- all_vectors %>%
  filter(vector %in% c(
    "v_CA16_4895",
    "v_CA16_4893",
    "v_CA16_4900",
    "v_CA16_2397",
    "v_CA16_401",
    "v_CA16_407",
    "v_CA16_406",
    "v_CA16_379",
    "v_CA16_425",
    "v_CA16_2449",
    "v_CA16_5603",
    "v_CA16_5651"
  )) %>%
  pull("vector")

# > get the data
census_data_all <- get_census(dataset = dataset,
                          level=level,
                          vectors=vectors, 
                          regions=regions, 
                          geo_format = "sf",
                          use_cache=TRUE)

# data preprocessing
census_data <- census_data_all %>%
  # keep only DA
  filter(Type == 'DA') %>%
  # select rename variable columns
  select(
    GeoUID,
    RegionName = "Region Name",
    Type,
    Dwellings,
    Households,
    Population,
    shelter_val_med = "v_CA16_4895: Median value of dwellings ($)",
    own_cost_med = "v_CA16_4893: Median monthly shelter costs for owned dwellings ($)",
    rent_cost_med = "v_CA16_4900: Median monthly shelter costs for rented dwellings ($)",
    pop_tot = "v_CA16_401: Population, 2016",
    pop_density = "v_CA16_406: Population density per square kilometre",
    land_area = "v_CA16_407: Land area in square kilometres",
    hhsize_avg = "v_CA16_425: Average household size",
    age_avg = "v_CA16_379: Average age",
    # income_tot_med = "v_CA16_2207: Median total income in 2015 among recipients ($)",
    # income_at_med = "v_CA16_2213: Median after-tax income in 2015 among recipients ($)",
    # income_mk_med = "v_CA16_2219: Median market income in 2015 among recipients ($)",
    income_hh_med = "v_CA16_2397: Median total income of households in 2015 ($)",
    famsize_avg = "v_CA16_2449: Average family size of economic families",
    emp_tot = "v_CA16_5603: Employed",
    self_emp_tot = "v_CA16_5651: Self-employed",
    land_area_shp =  "Area (sq km)"
  ) %>%
  mutate(
    shelter_cost_med = max(own_cost_med, rent_cost_med),
    emp_density = (emp_tot + self_emp_tot) / land_area,
    pop_emp_density = (pop_tot + emp_tot + self_emp_tot) / land_area
  ) %>%
  filter(pop_tot > 250) %>%
  filter(pop_density < 100e3) %>%
  filter(famsize_avg != 0) %>%
  mutate(
    own_cost_med = if_else(own_cost_med == 0, NA_real_, own_cost_med),
    rent_cost_med = if_else(rent_cost_med == 0, NA_real_, rent_cost_med),
    shelter_val_med = if_else(shelter_val_med == 0, NA_real_, shelter_val_med)
  ) %>%
  mutate(housing_income_ratio = shelter_val_med / income_hh_med) 


# Data EDA ----
# > map area ----

# map of shapes
census_data %>%
  leaflet() %>%
  addProviderTiles(providers$CartoDB.Positron) %>%
  addPolylines(color = 'green', weight = 2)

# build a template for maps
## common label
labels <- sprintf(
  "<strong>%s %s</strong><br/>Med. Shelter Value: $%gK <br/>Med. Income: $%gK <br/>House Price-Income Ratio: %g <br/>Avg. HH Size: %g <br/>Avg. Pop. Density: %g",
  census_data$RegionName,
  census_data$GeoUID,
  round(census_data$shelter_val_med,-3) / 1e3,
  round(census_data$income_hh_med,-3) / 1e3,
  census_data$housing_income_ratio,
  census_data$hhsize_avg,
  census_data$pop_density
) %>% lapply(htmltools::HTML)

# common map template
tidy_lf_map <-  function(df,
                         var,
                         var_name,
                         pal,
                         pal_var,
                         label,
                         labFormat = labelFormat(),
                         ...) {
  lf_map <- df %>%
    leaflet() %>%
    addProviderTiles(providers$CartoDB.Positron) %>%
    addPolygons(
      fillColor = ~ pal_var,
      opacity = 1,
      stroke = TRUE,
      weight = 0.5,
      color = "white",
      dashArray = "",
      fillOpacity = 0.7,
      highlight = highlightOptions(
        weight = 2,
        color = "#666",
        dashArray = "",
        fillOpacity = 0.7,
        bringToFront = TRUE
      ),
      label = label,
      labelOptions = labelOptions(
        style = list("font-weight" = "normal", padding = "3px 8px"),
        textsize = "15px",
        direction = "auto"
      )
    ) %>%
    addLegend(
      "bottomright",
      pal = pal,
      values = ~ var,
      title = var_name,
      labFormat = labFormat,
      opacity = 1
    )
  return(lf_map)
}

# map shelter value
bins <- c(0, 100e3, 500e3, 1e6, 1.5e6, 2e6, 2.5e6, 3e6, 5e6)
pal1 <- colorBin("Reds", domain = census_data$shelter_val_med, bins = bins)
shelter_map <-  census_data %>% tidy_lf_map(
  var = .$shelter_val_med,
  var_name = "Med. Housing Value",
  pal = pal1,
  pal_var = pal1(.$shelter_val_med),
  label = labels,
  labFormat = labelFormat(prefix = "$"),
)

# > map total HH income value
bins <- c(0, 25e3, 50e3, 75e3, 100e3, 125e3, 150e3, 200e3, 300e3)
pal1 <- colorBin("YlGn", domain = census_data$income_hh_med, bins = bins)
income_map <-  census_data %>% tidy_lf_map(
  var = .$income_hh_med,
  var_name = "Med. Household Income",
  pal = pal1,
  pal_var = pal1(.$income_hh_med),
  label = labels,
  labFormat = labelFormat(prefix = "$"),
)

# map house price to income ratio
bins <- c(0, 2, 4, 6, 8, 10, 20, 50, 100)
pal1 <- colorBin("YlOrRd", domain = census_data$housing_income_ratio, bins = bins)
housing_income_map <-  census_data %>% tidy_lf_map(
  var = .$housing_income_ratio,
  var_name = "Housing-income Ratio",
  pal = pal1,
  pal_var = pal1(.$housing_income_ratio),
  label = labels
  # labFormat = labelFormat(prefix = "$"),
)

# map HH size
bins <- c(1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5)
pal1 <- colorBin("YlGnBu", domain = census_data$hhsize_avg, bins = bins)
avgHHSize <-  census_data %>% tidy_lf_map(
  var = .$hhsize_avg,
  var_name = "Household Size",
  pal = pal1,
  pal_var = pal1(.$hhsize_avg),
  label = labels
  # labFormat = labelFormat(prefix = "$"),
)

# map Pop Density
bins <- c(10, 1e3, 2.5e3, 5e3, 10e3, 25e3, 50e3, 80e3)
pal1 <- colorBin("BuPu", domain = census_data$pop_density, bins = bins)
popDensity <-  census_data %>% tidy_lf_map(
  var = .$pop_density,
  var_name = "Population Density",
  pal = pal1,
  pal_var = pal1(.$pop_density),
  label = labels
  # labFormat = labelFormat(prefix = "$"),
)

latticeView(
  shelter_map,
  housing_income_map,
  avgHHSize,
  popDensity,
  sync = "all",
  ncol = 2
)

# > graphing ----

# housing value vs pop density
ggplot(census_data, aes(pop_density, shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)

# housing value vs log_e pop density
ggplot(census_data, aes(log(pop_density), shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)

# housing value vs hh income
ggplot(census_data, aes(income_hh_med, shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)

# housing value vs hh size
ggplot(census_data, aes(hhsize_avg, shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)

# housing value vs total employment
ggplot(census_data, aes(emp_tot, shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)
ggplot(census_data, aes(1/emp_tot, shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)

# housing value vs other variables
ggplot(census_data, aes(housing_income_ratio, shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)
ggplot(census_data, aes(own_cost_med, shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)
ggplot(census_data, aes(rent_cost_med, shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)
ggplot(census_data, aes(rent_cost_med, shelter_val_med)) +
  geom_point() +
  stat_smooth(method = lm)

# Simple model of housing value by DA ----
census_data_rev <- census_data %>%
  mutate(inv_pop_density = 1 / pop_density,
         inv_emp_tot = 1 / emp_tot,
         inv_pop_tot = 1/ pop_tot)

housing_value_model <-
  lm(shelter_val_med ~ income_hh_med + hhsize_avg + inv_pop_density + inv_emp_tot,
     data = census_data_rev)
summary(housing_value_model, corr = T)

housing_value_model <-
  lm(shelter_val_med ~ income_hh_med + hhsize_avg + inv_pop_tot + inv_emp_tot,
     data = census_data_rev)
summary(housing_value_model, corr = T)
# vcov(housing_value_model)

