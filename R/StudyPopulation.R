# @file StudyPopulation.R
#
# Copyright 2020 Observational Health Data Sciences and Informatics
#
# This file is part of CohortMethod
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Create a study population
#'
#' @details
#' Create a study population by enforcing certain inclusion and exclusion criteria, defining
#' a risk window, and determining which outcomes fall inside the risk window.
#'
#' @param plpData      An object of type \code{plpData} as generated using
#'                              \code{getDbplpData}.
#' @param population            If specified, this population will be used as the starting point instead of the
#'                              cohorts in the \code{plpData} object.
#' @param binary                Forces the outcomeCount to be 0 or 1 (use for binary prediction problems)                              
#' @param outcomeId             The  ID of the outcome.
#' @param includeAllOutcomes    (binary) indicating whether to include people with outcomes who are not observed for the whole at risk period
#' @param firstExposureOnly            Should only the first exposure per subject be included? Note that
#'                                     this is typically done in the \code{createStudyPopulation} function,
#' @param washoutPeriod                The mininum required continuous observation time prior to index
#'                                     date for a person to be included in the cohort.
#' @param removeSubjectsWithPriorOutcome  Remove subjects that have the outcome prior to the risk window start?
#' @param priorOutcomeLookback            How many days should we look back when identifying prior outcomes?
#' @param requireTimeAtRisk      Should subject without time at risk be removed?
#' @param minTimeAtRisk          The minimum number of days at risk required to be included
#' @param riskWindowStart        The start of the risk window (in days) relative to the \code{startAnchor}.
#' @param startAnchor	           The anchor point for the start of the risk window. Can be "cohort start" or "cohort end".
#' @param riskWindowEnd          The end of the risk window (in days) relative to the \code{endAnchor} parameter
#' @param endAnchor              The anchor point for the end of the risk window. Can be "cohort start" or "cohort end".
#' @param verbosity              Sets the level of the verbosity. If the log level is at or higher in priority than the logger threshold, a message will print. The levels are:
#'                               \itemize{
#'                               \item{DEBUG}{Highest verbosity showing all debug statements}
#'                               \item{TRACE}{Showing information about start and end of steps}
#'                               \item{INFO}{Show informative information (Default)}
#'                               \item{WARN}{Show warning messages}
#'                               \item{ERROR}{Show error messages}
#'                               \item{FATAL}{Be silent except for fatal errors} 
#'                               }
#' @param addExposureDaysToStart DEPRECATED: Add the length of exposure the start of the risk window? Use \code{startAnchor} instead.
#' @param addExposureDaysToEnd   DEPRECATED: Add the length of exposure the risk window? Use \code{endAnchor} instead.
#' @param ...                   Other inputs
#'
#' @return
#' A data frame specifying the study population. This data frame will have the following columns:
#' \describe{
#' \item{rowId}{A unique identifier for an exposure}
#' \item{subjectId}{The person ID of the subject}
#' \item{cohortStartdate}{The index date}
#' \item{outcomeCount}{The number of outcomes observed during the risk window}
#' \item{timeAtRisk}{The number of days in the risk window}
#' \item{survivalTime}{The number of days until either the outcome or the end of the risk window}
#' }
#'
#' @export
createStudyPopulation <- function(plpData,
                                  population = NULL,
                                  outcomeId,
                                  binary = T,
                                  includeAllOutcomes = T,
                                  firstExposureOnly = FALSE,
                                  washoutPeriod = 0,
                                  removeSubjectsWithPriorOutcome = TRUE,
                                  priorOutcomeLookback = 99999,
                                  requireTimeAtRisk = F,
                                  minTimeAtRisk=365, # outcome nonoutcome
                                  riskWindowStart = 0,
                                  startAnchor = "cohort start",
                                  riskWindowEnd = 365,
                                  endAnchor = "cohort start",
                                  verbosity = "INFO",
                                  addExposureDaysToStart,
                                  addExposureDaysToEnd,
                                  ...) {
  
  
  # If addExposureDaysToStart is specified used it but give warning
  if(!missing(addExposureDaysToStart)){
    if(is.null(startAnchor)){
      warning('addExposureDaysToStart is depreciated - please use startAnchor instead') 
      startAnchor <- ifelse(addExposureDaysToStart, 'cohort end','cohort start')
    } else {
      warning('addExposureDaysToStart specificed so being used')
      warning('addExposureDaysToStart is depreciated - please use startAnchor instead') 
      startAnchor <- ifelse(addExposureDaysToStart, 'cohort end','cohort start')
    }
  }
  
  if(!missing(addExposureDaysToEnd)){
    if(is.null(endAnchor)){
      warning('addExposureDaysToEnd is depreciated - please use endAnchor instead') 
      endAnchor <- ifelse(addExposureDaysToEnd, 'cohort end','cohort start')
    } else {
      warning('addExposureDaysToEnd specificed so being used')
      warning('addExposureDaysToEnd is depreciated - please use endAnchor instead') 
      endAnchor <- ifelse(addExposureDaysToEnd, 'cohort end','cohort start')
    }
  }
  
  if(missing(verbosity)){
    verbosity <- "INFO"
  } else{
    if(!verbosity%in%c("DEBUG","TRACE","INFO","WARN","FATAL","ERROR")){
      stop('Incorrect verbosity string')
    }
  }
  # check logger
  if(length(ParallelLogger::getLoggers())==0){
    logger <- ParallelLogger::createLogger(name = "SIMPLE",
                                        threshold = verbosity,
                                        appenders = list(ParallelLogger::createConsoleAppender(layout = ParallelLogger::layoutTimestamp)))
    ParallelLogger::registerLogger(logger)
  }
  
  
  # parameter checks
  if(!class(plpData)%in%c('plpData')){
    ParallelLogger::logError('Check plpData format')
    stop('Wrong plpData input')
  }
  ParallelLogger::logDebug(paste0('outcomeId: ', outcomeId))
  checkNotNull(outcomeId)
  ParallelLogger::logDebug(paste0('binary: ', binary))
  checkBoolean(binary)
  ParallelLogger::logDebug(paste0('includeAllOutcomes: ', includeAllOutcomes))
  checkBoolean(includeAllOutcomes)
  ParallelLogger::logDebug(paste0('firstExposureOnly: ', firstExposureOnly))
  checkBoolean(firstExposureOnly)
  ParallelLogger::logDebug(paste0('washoutPeriod: ', washoutPeriod))
  checkHigherEqual(washoutPeriod,0)
  ParallelLogger::logDebug(paste0('removeSubjectsWithPriorOutcome: ', removeSubjectsWithPriorOutcome))
  checkBoolean(removeSubjectsWithPriorOutcome)
  if (removeSubjectsWithPriorOutcome){
    ParallelLogger::logDebug(paste0('priorOutcomeLookback: ', priorOutcomeLookback))
    checkHigher(priorOutcomeLookback,0)
  }
  ParallelLogger::logDebug(paste0('requireTimeAtRisk: ', requireTimeAtRisk))
  checkBoolean(requireTimeAtRisk)
  ParallelLogger::logDebug(paste0('minTimeAtRisk: ', minTimeAtRisk))
  checkHigherEqual(minTimeAtRisk,0)
  ParallelLogger::logDebug(paste0('riskWindowStart: ', riskWindowStart))
  checkHigherEqual(riskWindowStart,0)
  ParallelLogger::logDebug(paste0('startAnchor: ', startAnchor))
  if(!startAnchor%in%c('cohort start', 'cohort end')){
    stop('Incorrect startAnchor')
  }
  ParallelLogger::logDebug(paste0('riskWindowEnd: ', riskWindowEnd))
  checkHigherEqual(riskWindowEnd,0)
  ParallelLogger::logDebug(paste0('endAnchor: ', endAnchor))
  if(!endAnchor%in%c('cohort start', 'cohort end')){
    stop('Incorrect startAnchor')
  }
  
  if(requireTimeAtRisk){
    if(startAnchor==endAnchor){
      if(minTimeAtRisk>(riskWindowEnd-riskWindowStart)){
        warning('issue: minTimeAtRisk is greater than max possible time-at-risk')
      }
    }
  }
  
  if (is.null(population)) {
    population <- plpData$cohorts
  }
  
  # save the metadata
  metaData <- attr(population, "metaData")
  metaData$outcomeId <- outcomeId
  metaData$binary <- binary
  metaData$includeAllOutcomes <- includeAllOutcomes
  metaData$firstExposureOnly = firstExposureOnly
  metaData$washoutPeriod = washoutPeriod
  metaData$removeSubjectsWithPriorOutcome = removeSubjectsWithPriorOutcome
  metaData$priorOutcomeLookback = priorOutcomeLookback
  metaData$requireTimeAtRisk = requireTimeAtRisk
  metaData$minTimeAtRisk=minTimeAtRisk
  metaData$riskWindowStart = riskWindowStart
  metaData$startAnchor = startAnchor
  metaData$riskWindowEnd = riskWindowEnd
  metaData$endAnchor = endAnchor
  
  # set the existing attrition
  if(is.null(metaData$attrition)){
    metaData$attrition <- attr(plpData$cohorts,  'metaData')$attrition
  }
  if(!is.null(metaData$attrition)){
    metaData$attrition <- data.frame(outcomeId = metaData$attrition$outcomeId,
                                     description = metaData$attrition$description,
                                     targetCount = metaData$attrition$targetCount,
                                     uniquePeople = metaData$attrition$uniquePeople,
                                     outcomes = metaData$attrition$outcomes)
    if(sum(metaData$attrition$outcomeId==outcomeId)>0){
      metaData$attrition <- metaData$attrition[metaData$attrition$outcomeId==outcomeId,]
    } else{
      metaData$attrition <- NULL
    }
  }
  
  
  # ADD TAR
  oId <- outcomeId
  population <- population %>% 
    dplyr::mutate(startAnchor = startAnchor, startDay = riskWindowStart,
                  endAnchor = endAnchor, endDay = riskWindowEnd) %>%
    dplyr::mutate(tarStart = ifelse(startAnchor == 'cohort start', startDay, startDay+ daysToCohortEnd),
                  tarEnd = ifelse(endAnchor == 'cohort start', endDay, endDay+ daysToCohortEnd))  %>%
    dplyr::mutate(tarEnd = ifelse(tarEnd>daysToObsEnd, daysToObsEnd,tarEnd ))
    
    
  
  # get the outcomes during TAR
  outcomeTAR <- population %>% 
    dplyr::inner_join(plpData$outcomes, by ='rowId') %>% 
    dplyr::filter(outcomeId == get('oId'))  %>% 
    dplyr::select(rowId, daysToEvent, tarStart, tarEnd) %>% 
    dplyr::filter(daysToEvent >= tarStart & daysToEvent <= tarEnd)  %>%
    dplyr::group_by(rowId) %>%
    dplyr::summarise(first = min(daysToEvent),
                     ocount = length(unique(daysToEvent)))  %>% 
    dplyr::select(rowId, first, ocount)
  
  
  population <- population %>%
    dplyr::left_join(outcomeTAR, by = 'rowId')
  
  
  # get the initial row
  attrRow <- population %>% dplyr::group_by() %>%
    dplyr::summarise(outcomeId = get('oId'),
                     description = 'Initial plpData cohort or population',
                     targetCount = length(rowId),
                     uniquePeople = length(unique(subjectId)),
                     outcomes = sum(!is.na(first)))  
  metaData$attrition <- rbind(metaData$attrition, attrRow)

  
  if (firstExposureOnly) {
    ParallelLogger::logTrace(paste("Restricting to first exposure"))
    
    population <- population %>%
      dplyr::arrange(subjectId,cohortStartDate) %>%
      dplyr::group_by(subjectId) %>%
      dplyr::filter(dplyr::row_number(subjectId)==1)
    
    attrRow <- population %>% dplyr::group_by() %>%
      dplyr::summarise(outcomeId = get('oId'),
                       description = 'First Exposure',
                       targetCount = length(rowId),
                       uniquePeople = length(unique(subjectId)),
                       outcomes = sum(!is.na(first)))  
    metaData$attrition <- rbind(metaData$attrition, attrRow)
  }

  
  if(washoutPeriod) {
    ParallelLogger::logTrace(paste("Requiring", washoutPeriod, "days of observation prior index date"))
    msg <- paste("At least", washoutPeriod, "days of observation prior")
    population <- population %>%
      dplyr::mutate(washoutPeriod = washoutPeriod) %>%
      dplyr::filter(daysFromObsStart >= washoutPeriod)
    
    attrRow <- population %>% dplyr::group_by() %>%
      dplyr::summarise(outcomeId = get('oId'),
                       description = msg,
                       targetCount = length(rowId),
                       uniquePeople = length(unique(subjectId)),
                       outcomes = sum(!is.na(first)))  
    metaData$attrition <- rbind(metaData$attrition, attrRow)
  }
  
  if(removeSubjectsWithPriorOutcome) {
      ParallelLogger::logTrace("Removing subjects with prior outcomes (if any)")
    
    # get the outcomes during TAR
    outcomeBefore <- population %>% 
      dplyr::inner_join(plpData$outcomes, by ='rowId') %>% 
      dplyr::filter(outcomeId == get('oId'))  %>% 
      dplyr::select(rowId, daysToEvent, tarStart) %>% 
      dplyr::filter(daysToEvent < tarStart)  %>%
      dplyr::group_by(rowId) %>%
      dplyr::summarise(first = min(daysToEvent))  %>% 
      dplyr::select(rowId)
      
    population <- population %>%
      dplyr::filter(!rowId %in% outcomeBefore$rowId )
      
      attrRow <- population %>% dplyr::group_by() %>%
        dplyr::summarise(outcomeId = get('oId'),
                         description = "No prior outcome",
                         targetCount = length(rowId),
                         uniquePeople = length(unique(subjectId)),
                         outcomes = sum(!is.na(first)))  
      metaData$attrition <- rbind(metaData$attrition, attrRow)
  }
  

  if (requireTimeAtRisk) {
    if(includeAllOutcomes){
      ParallelLogger::logTrace("Removing non outcome subjects with insufficient time at risk (if any)")
      
      
      population <- population %>%
        dplyr::filter(!is.na(first) | tarEnd >= tarStart + minTimeAtRisk )
      
      attrRow <- population %>% dplyr::group_by() %>%
        dplyr::summarise(outcomeId = get('oId'),
                         description = "Removing non-outcome subjects with insufficient time at risk (if any)",
                         targetCount = length(rowId),
                         uniquePeople = length(unique(subjectId)),
                         outcomes = sum(!is.na(first)))  
      metaData$attrition <- rbind(metaData$attrition, attrRow)

    }
    else {
      ParallelLogger::logTrace("Removing subjects with insufficient time at risk (if any)")
      
      population <- population %>%
        dplyr::filter( tarEnd >= tarStart + minTimeAtRisk )
      
      attrRow <- population %>% dplyr::group_by() %>%
        dplyr::summarise(outcomeId = get('oId'),
                         description = "Removing subjects with insufficient time at risk (if any)",
                         targetCount = length(rowId),
                         uniquePeople = length(unique(subjectId)),
                         outcomes = sum(!is.na(first)))  
      metaData$attrition <- rbind(metaData$attrition, attrRow)
      
    }
  } else {
    # remve any patients with negative timeAtRisk
    ParallelLogger::logTrace("Removing subjects with no time at risk (if any)")
    
    population <- population %>%
      dplyr::filter( tarEnd >= tarStart )
    
    attrRow <- population %>% dplyr::group_by() %>%
      dplyr::summarise(outcomeId = get('oId'),
                       description = "Removing subjects with no time at risk (if any))",
                       targetCount = length(rowId),
                       uniquePeople = length(unique(subjectId)),
                       outcomes = sum(!is.na(first)))  
    metaData$attrition <- rbind(metaData$attrition, attrRow)
  }
  
  # now add columns to pop
  
  if(binary){
    ParallelLogger::logInfo("Outcome is 0 or 1")
  population <- population %>%
    dplyr::mutate(outcomeCount = ifelse(is.na(ocount),0,1))
  } else{
    ParallelLogger::logTrace("Outcome is count")
    population <- population %>%
      dplyr::mutate(outcomeCount = ifelse(is.na(ocount),0,ocount))
  }
  
  population <- population %>%
    dplyr::mutate(timeAtRisk = tarEnd - tarStart + 1 ,
                  survivalTime = ifelse(outcomeCount == 0, tarEnd -tarStart + 1, first - tarStart + 1),
                  daysToEvent = first) %>%
    dplyr::select(rowId, subjectId, cohortId, cohortStartDate, daysFromObsStart,
                  daysToCohortEnd, daysToObsEnd, ageYear, gender,
                  outcomeCount, timeAtRisk, daysToEvent, survivalTime)

    # check outcome still there
    if(sum(!is.na(population$daysToEvent))==0){
      return(NULL)
      ParallelLogger::logWarn('No outcomes left...')
    }
  
  population <- as.data.frame(population)
  
  attr(population, "metaData") <- metaData
  return(population)
}


#' Get the attrition table for a population
#'
#' @param object   Either an object of type \code{plpData}, a population object generated by functions
#'                     like \code{createStudyPopulation}, or an object of type \code{outcomeModel}.
#'
#' @return
#' A data frame specifying the number of people and exposures in the population after specific steps of filtering.
#'
#'
#' @export
getAttritionTable <- function(object) {
  if (is(object, "plpData")) {
    object = object$cohorts
  }
  if (methods::is(object, "outcomeModel")){
    return(object$attrition)
  } else {
    return(attr(object, "metaData")$attrition)
  }
}


getCounts <- function(population,description = "") {
  persons <- length(unique(population$subjectId))
  targets <- nrow(population)
  
  counts <- data.frame(description = description,
                       targetCount= targets,
                       uniquePeople = persons)
  return(counts)
}

getCounts2 <- function(cohort,outcomes, description = "") {
  persons <- length(unique(cohort$subjectId))
  targets <- nrow(cohort)
  
  outcomes <- aggregate(cbind(count = outcomeId) ~ outcomeId, 
                        data = outcomes, 
                        FUN = function(x){NROW(x)})
  
  counts <- data.frame(outcomeId = outcomes$outcomeId,
                       description = description,
                       targetCount= targets,
                       uniquePeople = persons,
                       outcomes = outcomes$count)
  return(counts)
}

