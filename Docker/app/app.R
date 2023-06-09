#Empty the R environment
rm(list = ls())
options(shiny.appmode = "shiny")

#Set your working environment to the location where your current source file is saved into.
# setwd("F:/bridgeDb/GitHubRepositories/BridgeDb-Shiny/")

# Load required packages
library(dplyr)
library(httr)
library(ggplot2)
library(shiny)
# library(edgeR)
library(DT)
library(data.table)
library(rjson)


#Reading the required files
dataSources <- data.table::fread("input/dataSource.csv")

#Define a function for adding mapping cardinality
add_mapping_cardinality <- function(dataFile) {
  
  # Calculate counts
  dataFile <- dataFile %>%
    group_by(primaryID) %>% 
    mutate(count_primaryID = n(),
           count_primaryID = ifelse(primaryID == "Entry Withdrawn", 0, count_primaryID)) %>%
    group_by(secondaryID) %>% 
    mutate(count_secondaryID = n()) %>%
    ungroup()
  
  # Add mapping_cardinality_sec2pri column
  dataFile <- dataFile %>%
    mutate(mapping_cardinality_sec2pri = ifelse(count_secondaryID == 1 & count_primaryID == 1,
                                                "1:1", ifelse(
                                                  count_secondaryID > 1 & count_primaryID == 1,
                                                  "1:n", ifelse(
                                                    count_secondaryID == 1 & count_primaryID > 1,
                                                    "n:1", ifelse(
                                                      count_secondaryID == 1 & count_primaryID == 0,
                                                      "1:0", ifelse(
                                                        count_secondaryID > 1 & count_primaryID > 1,
                                                        "n:n", NA
                                                      ))))))
  # Return the updated data
  return(select(dataFile, -c(count_primaryID, count_secondaryID)))
}


## HMDB
HMDB <- data.table::fread("input/hmdb_secIds.tsv")
primaryIDs_HMDB <- HMDB$primaryID
## ChEBI
ChEBI <- data.table::fread("input/ChEBI_secIds.tsv")
primaryIDs_ChEBI <- ChEBI$primaryID
## Wikidata
Wikidata <- data.table::fread("input/wikidata_secIds.tsv")
primaryIDs_Wikidata <- Wikidata$primaryID
## HGNC
HGNC.ID <- data.table::fread("input/hgnc.id_secIds.tsv")
primaryIDs_HGNC.ID <- unlist(data.table::fread("input/hgnc.id_priIds.tsv"), use.names = FALSE)
HGNC <- data.table::fread("input/hgnc.symbol_secIds.tsv")
primaryIDs_HGNC <- unlist(data.table::fread("input/hgnc.symbol_priIds.tsv"), use.names = FALSE)


options(rsconnect.max.bundle.files = 3145728000)

# Piechart
piechart_theme <- theme_minimal() +
  theme(
    axis.title = element_blank(),
    panel.border = element_blank(),
    panel.grid = element_blank(),
    axis.ticks = element_blank(),
    legend.position = "none",
    axis.text.x = element_blank(),
    axis.text.y = element_text(size = 16),
    plot.title = element_text(size = 16, face = "bold")
  )

# define a function for XrefBatch mapping
Xref_function <- function(identifiers, inputSpecies = "Human",
                          inputSystemCode = "HGNC", outputSystemCode = "All") {
  
  # Preparing the query
  input_source <- dataSources$systemCode[dataSources$source == inputSystemCode]
  if(length(identifiers) != 0) {
    if(length(identifiers) == 1) {
      post_con <- paste0(identifiers, "\t", input_source, "\n")
    } else {
      post_con <- paste0(identifiers, collapse = paste0("\t", input_source, "\n"))
      post_con <- paste0(post_con, "\t", input_source, "\n")
    }
    # Setting up the query url
    url <- "https://webservice.bridgedb.org"
    query_link  <- paste(url, inputSpecies, "xrefsBatch", sep = "/")
    # Getting the response to the query
    res <- tryCatch({
      POST(url = query_link, body = post_con)
    }, error = function(e) {
      message("Error: ", e$message)
      return(NULL)
    })
    # Extracting the content in the raw text format
    out <- content(res, as="text")

    if (jsonlite::validate(out)) { # check if JSON string is valid
      res <- fromJSON(json_str = out)
      # Convert to data frame
      df <- do.call(rbind, lapply(names(res), function(name) {
        data.frame(
          identifier = rep(name, length(res[[name]]$`result set`)),
          identifier.source = rep(res[[name]]$datasource, length(res[[name]]$`result set`)),
          target = gsub("^[^:]*:", "", res[[name]]$`result set`),
          target.source = sapply(strsplit(res[[name]]$`result set`, ":"), `[`, 1)
        )
      })) %>% 
        mutate(target.source = dataSources$source[match(target.source, dataSources$to_map)])
      if(outputSystemCode == "All") {
        return(df)
      } else {
        return(df %>% filter(target.source == outputSystemCode))
      }
    } else {
      return(paste0("The response is not a valid JSON string."))
    }
  }
  
}

# Xref_metabolite_function <- function(query, 
#                                      inputSystemCode = "Ch", outputSystemCode = "All") {
#   
#   # Preparing the query link.
#   ## Setting up the query url.
#   url <- "https://webservice.bridgedb.org/Human"
#   if(outputSystemCode == "All") {
#     query_link  <- paste(url, "xrefs", inputSystemCode, query, sep = "/")
#   } else {
#     query_link  <- paste(url, "xrefs", inputSystemCode, query, outputSystemCode, sep = "/")
#   }
#   
#   
#   # Getting the response to the query.
#   q_res <- GET(query_link)
#   
#   # Extracting the content in the raw text format.
#   dat <- content(q_res, as = "text")
#   
#   if(dat == "{}") {
#     warning(paste0("The query did not return a response."))
#   }
#   
#   # Processing the raw content to get a data frame.
#   dat <- as.data.frame(strsplit(dat, ",")[[1]])
#   dat <- unlist(apply(dat, 1, strsplit, '":"'))
#   dat <- matrix(dat, ncol = 2, byrow = TRUE)
#   dat <- gsub('^[^:]*:|[{}\\\\/""]', "", dat)
#   dat <- data.frame (identifier = rep(query, nrow(dat)),
#                      target = dat[,1],
#                      source = dat[,2])
#   
#   return(dat)
#   
# }

#### Shinny App
ui <- fluidPage(
  shinyjs::useShinyjs(), # needed for download button to work
  tags$head(
    tags$style(
      HTML('<hr style = "border-color: #0088cc;">
           <style>
             .main-panel {
               padding-top: 60px; /* adjust this value as needed */
             }
             .my-plot {
               height: 300px; /* set the height of the plot */
               margin-bottom: 10px; /* add a small margin at the bottom */
             }
             .my-table {
               height: 500px; /* set the height of the table */
               overflow-y: auto; /* add a vertical scrollbar if necessary */
             }
             .navbar {
               margin-bottom: 0px !important;
               margin-top: 0px!important!
             }
             .tab-content {
               padding-top: 0px !important;
               min-height: 570px;
             }
             .input-group {
               margin-bottom: 0px;
             }
         </style>
      ')
    )
  ),# Set the page title and add a horizontal line separator
  # Add a title panel
  titlePanel(
    div(
      div(
        div(
          h5(""),
          strong("BridgeDb-Shiny"),
          style = "float:left;justify-content: flex-end;"
        ),
        div(
          imageOutput("Maastricht_logo"),
          style = "display: flex; align-items: right; justify-content: flex-end;"
        ),
        style = "display:flex; justify-content: space-between;margin: 0px; height: 70px;"
      ),
      div(style = "margin-top: -15px"),
      div(
        h4("A user friendly application for identifier mapping"),
        style = "text-align: left;"
      )
    )
  ),
  # Add a tabset panel with three tabs
  navbarPage(
    title = NULL,
    # Tab 1: About
    tabPanel(
      "About", 
      icon = icon("book"),
      align = "justify",
      # Add a summary section
      h3(strong("Summary")),
      # onclick = "ga('send', 'event', 'click', 'link')",
      p("Biological entities such as genes, proteins, complexes, and metabolites often have diverse identifiers across various databases, which pose a challenge for data integration. To solve this problem, identifier mapping is required to convert identifiers from one database to corresponding entities from other databases."),
      imageOutput("bridgeDb_logo", height = "70px"),
      p("BridgeDb (bridgedb.org) is an open source tool introduced in 2010 that connects identifiers from various biological databases and related resources, facilitating data harmonization and multi-omics analysis. BridgeDb is an ELIXIR Recommended Interoperability Resource (RIR) and provides mappings for genes and proteins for 35 species, metabolites, metabolic reactions, diseases, complexes, human coronaviruses, and publications. It includes:",
        tags$ul(
          tags$li("a Java library for software integration,"),
          tags$li("a REST-API for programmatic access from any programming language,"),
          tags$li("a dedicated R package,"),
          tags$li("a Python package,"),
          tags$li("and example code for Matlab integration through the webservice."),
        )
      ),
      br(),
      h4(strong("The secondary identifier challenge")),
      p("After mapping identifiers from one database to another, integrating data can remain a challenge due to the presence of", 
        HTML("<b>retired, deleted, split, and/or merged identifiers</b>"), 
        " currently present in databases and datasets alike. These outdated identifiers are called",
        HTML("<b><span style='font-size:15px;'>“secondary”</span></b>"),
        " while the identifiers currently supported by databases are referred to as",
        HTML("<b><span style='font-size:15px;'>“primary”</span></b>"),
        ". The presence of secondary identifiers in a used dataset or database can lead to information loss and hinders effective data integration. While some tools exist to convert secondary identifiers to current ones, these tools only support one type of data (either genes/proteins or metabolites): ",
        tags$ul(
          tags$li("https://www.genenames.org/tools/multi-symbol-checker/"),
          tags$li("https://www.metaboanalyst.ca/MetaboAnalyst/upload/ConvertView.xhtml")
        ),
        "These tools currently do not have an API or other form of programmatic access, leading to issues in big OMICS data analysis."),
      br(),
      h4(strong("BridgeDb-Shiny")),
      p("To address the challenges of integrating data from different biological sources that contain secondary identifiers, we developed a user-friendly Shiny app called BridgeDb-Shiny, which provides two key functions:",
        tags$ul(
          tags$li(style = "list-style-type: decimal;",
                  HTML("<b><span style='font-size:15px;'>XRefBatch mapping:</span></b>"),
                  br(),
                  "uses BridgeDb's REST-API to convert identifiers."),
          tags$li(style = "list-style-type: decimal;",
                  HTML("<b><span style='font-size:15px;'>Secondary-to-Primary (sec2pri) mapping:</span></b>"),
                  br(),
                  "provides statistics on the percentage of secondary identifiers in the dataset and converts outdated secondary identifiers to current primary identifiers, if available.",
                  "The sec2pri mapping functionality currently covers secondary identifiers from",
                  HTML("<b>HGNC</b>"), ", ",
                  HTML("<b>HMDB</b>"), ", ",
                  HTML("<b>ChEBI</b>"), "and ",
                  HTML("<b>Wikidata</b>"),
                  "which can be converted to the corresponding primary identifier from the initial database.",
                  "After this step, the XrefBatch mapping can be used to convert the primary-ID-enhanced dataset to any other database currently supported by BridgeDb:",
                  tags$ul(
                    tags$li(
                      "The full overview of supported databases is available on the BridgeDb website (bridgedb.org/pages/system-codes)."
                    )
                  )
          )
        )
      ),
      p("The metadata for the latest update of the mapping files is also available to users for queries within the app."),
      br(),
      p(HTML("<b>Future development </b>"),
        "entails updating the Secondary-to-Primary identifier mapping files regularly via GitHub Actions to ensure accuracy."),
      br(),
      hr(),
      # Add a citation section
      h4("How to Cite BridgeDb"),
      p("van Iersel, Martijn P et al. “The BridgeDb framework: standardized access to gene, protein and metabolite identifier mapping services.” BMC bioinformatics vol. 11 5. 4 Jan. 2010."),
      p("doi:10.1186/1471-2105-11-5")
    ),
    # Tab 2: XrefBatch
    tabPanel(
      "XRefBatch mapping", 
      icon = icon("table"),
      div(
        style = "margin-top: 15px;",
        # Add a sidebar layout
        sidebarLayout(
          # Add a sidebar panel with input controls
          sidebarPanel(
            div(style = "margin-top: -10px"),
            
            # Render the input options for selecting a identifier type
            radioButtons ("type", "Choose identifier type:", inline = TRUE,
                          c ("Gene/Protein" = "gene", "Metabolites" = "metabolite"),
                          selected = "metabolite" 
                          ),
            # Render the input options for selecting a species
            conditionalPanel(
              condition = "input.type == 'gene'",
              uiOutput('inputSpecies')
            ),
            div(style = "margin-top: -5px"),
            # Add a file input for uploading a text file containing identifiers
            fileInput(
              "XrefBatch_identifiers_file",
              "Upload identifiers File",
              accept = c(".csv", ".xlsx", ".xls", ".tsv", ".txt"),
              placeholder = "Please upload file.."
            ),
            div(style = "margin-top: -30px"),
            # Add a text area input for entering identifiers
            textAreaInput(
              'XrefBatch_identifiers',
              'or insert identifier(s) here',
              value = NULL,
              width = NULL,
              placeholder = 'one identifier per row'
            ),
            div(style = "margin-top: -10px"),
            # Render the input options for selecting a data source
            uiOutput('inputDataSource'),
            div(style = "margin-top: -10px"),
            # Render the input options for selecting an output data source
            uiOutput('outputDataSource'),
            # Add buttons for performing the identifier mapping and clearing the list
            div(style = "margin-top: -10px"),
            div(
              actionButton(
                "XrefBatch_get", "Bridge",
                style = "color: white; background-color: gray; border-color: black"),
              actionButton(
                "XrefBatch_clear_list", "Clear",
                style = "color: white; background-color: gray; border-color: black"),
              br(),
              br(),
              div(style = "margin-top: -10px"),
              selectInput(
                inputId = "XrefBatch_download_format",
                label = "Choose a download format:",
                choices = c("csv", "tsv")
              ),
              div(style = "margin-top: -10px"),
              downloadButton(
                outputId = "XrefBatch_download", 
                label = "Download results", 
                style = "color: white; background-color: gray; border-color: black"
              ),
              div(style = "margin-top: -10px")
            ),
            width = 3
          ),
          # Add a main panel for displaying the bridge list
          mainPanel(
            div(DTOutput("XrefBatch_mapping_results", height = "500px")),
            width = 9
          )
        )
      ),
      style = "height: 300px;"
    ),
    # Tab 3: Sec2pri
    tabPanel(
      "Sec2pri mapping", 
      icon = icon("table"),
      div(
        style = "margin-top: 15px;",
        # Add a sidebar layout
        sidebarLayout(
          # Add a sidebar panel with input controls
          sidebarPanel(
            div(style = "margin-top: -10px"),
            # Add a file input for uploading a text file containing identifiers
            fileInput(
              "sec2pri_identifiers_file",
              "Upload identifiers File",
              accept = c(".csv", ".xlsx", ".xls", ".tsv", ".txt"),
              placeholder = "Please upload file.."
            ),
            div(style = "margin-top: -30px"),
            # Add a text area input for entering identifiers
            textAreaInput(
              'sec2pri_identifiers', 
              'or insert identifier(s) here', 
              value = "", 
              width = NULL, 
              placeholder = 'one identifier per row'
            ),
            div(style = "margin-top: -10px"),
            # Render the input options for selecting a data source
            uiOutput('dataSource'),
            # Add buttons for performing the identifier mapping and clearing the list
            div(style = "margin-top: -10px"),
            div(
              actionButton(
                "sec2pri_get", "Bridge",
                style = "color: white; background-color: gray; border-color: black"),
              actionButton(
                "sec2pri_clear_list", "Clear",
                style = "color: white; background-color: gray; border-color: black"),
              br(),
              br(),
              div(style = "margin-top: -10px"),
              selectInput(
                inputId = "sec2pri_download_format",
                label = "Choose a download format:",
                choices = c("csv", "tsv")
              ),
              div(style = "margin-top: -10px"),
              downloadButton(
                outputId = "sec2pri_download",
                label = "Download results", 
                style = "color: white; background-color: gray; border-color: black"
              ),
              div(style = "margin-top: -10px")
            ),
            width = 3
          ),
          # Add a main panel for displaying the bridge list
          mainPanel(
            div(htmlOutput("sec2pri_metadata")),
            div(plotOutput("sec2pri_piechart_results", height = "300px"), class = "my-plot"),
            div(DTOutput("sec2pri_mapping_results"), style = "margin-top: -100px;"),
            width = 9
          )
        )
      )
    ),
    # Tab 4: Contact us
    tabPanel(
      "Contact us",
      icon = icon("envelope"),
      div(
        style = "margin-top: 15px;",
        # Add a contact us section
        br(),
        p(HTML("<b><span style='font-size:16px;'>For questions and comments:</span></b>")),
        p(HTML("<b>Tooba Abbassi-Daloii</b>"), ": t.abbassidaloii@maastrichtuniversity.nl"),
        p(HTML("<b>Ozan Cinar</b>"), ": ozan.cinar@maastrichtuniversity.nl"),
        br(),
        p("Department Bioinformatics - BiGCaT"),
        p("NUTRIM, Maastricht University, Maastricht, The Netherlands")
      )
    ),
    inverse = T
  ),
  div(
    style = "display: flex; flex-direction: column;",
    div(style = "flex: 0;",
    ),
    div(
      imageOutput("bridgeDb_logo_wide", height = "70px"),
      style = "background-color: white; text-align: center; padding: 10px;"
    ),
    div(
      p("licensed under the ", a("Apache License, version 2.0", href = "https://www.apache.org/licenses/LICENSE-2.0")),
      style = "text-align: center; padding: 50px;"
    )
  )
)

server <- function(input, output, session) {
  #Maastricht logo
  output$Maastricht_logo <- renderImage({
    list(src = "www/Maastricht.png",
         width = "280px",
         height = "70px", 
         contentType = "image/png")
  }, deleteFile = FALSE)
  
  #XrefBatch tab
  ##Define the input options based
  ### Species
  observe({
    if(input$type == "gene") {
      output$inputSpecies <- renderUI({
        # Render the input options for selecting a species
        selectInput(
          inputId = 'inputSpecies',
          label = 'Choose species:',
          choices = c("Human"),
          selected = "Human"
        )
      })
    } else if(input$type == "metabolite") {
      output$inputSpecies <- renderUI({
        # Render an empty UI if identifier type is not gene
        NULL
      })
    }
  })
  ### Input data source
  observe({
    if(input$type == "gene") {
      output$inputDataSource <- renderUI({
        # Render the input options for selecting a species
        selectInput(
          inputId = 'inputDataSource', 
          label = 'Choose the input data source:',
          choices = sort(dataSources$source[dataSources$type == "gene"]),
          selected = "HGNC"
        )
      })
    } else if(input$type == "metabolite") {
      output$inputDataSource <- renderUI({
        # Render the input options for selecting a species
        selectInput(
          inputId = 'inputDataSource', 
          label = 'Choose the input data source:',
          choices = sort(dataSources$source[dataSources$type == "metabolite"]),
          selected = "ChEBI"
        )
      })
    }
  })
  ### Output data source
  observe({
    if(input$type == "gene") {
      output$outputDataSource <- renderUI({
        # Render the input options for selecting a species
        selectInput(
          inputId = 'outputDataSource', 
          label = 'Choose one or more output data source:', 
          choices = c("All", sort(dataSources$source[dataSources$type == "gene"])),
          selected = "Ensembl"
        )
      })
    } else if(input$type == "metabolite") {
      output$outputDataSource <- renderUI({
        # Render the input options for selecting a species
        selectInput(
          inputId = 'outputDataSource', 
          label = 'Choose one or more output data source:', 
          choices = c("All", sort(dataSources$source[dataSources$type == "metabolite"])),
          selected = "HMDB"
        )
      })
    }
  })
  
  XrefBatch_input_file <- reactiveVal(NULL)
  observeEvent(input$XrefBatch_identifiers_file, {
    if(!is.null(input$XrefBatch_identifiers_file)){
      XrefBatch_input_file(input$XrefBatch_identifiers_file)
    }
  })
  
  # Function to make a vector for input identifiers
  identifiersList <- reactive({
    if(!is.null(XrefBatch_input_file())){
      print("Reading identifiers from file...")
      input_ids <- readLines(XrefBatch_input_file()$datapath)
      # Remove empty or whitespace-only last line
      last_line <- input_ids[length(input_ids)]
      if(nchar(trimws(last_line)) == 0){
        input_ids <- input_ids[-length(input_ids)]
      }
      # Split identifiers on newline, comma, or space
      input_ids <- unlist(strsplit(input_ids, '\\"|\n|\t|,|\\s+', perl = TRUE))
      # Remove empty strings and return the list of identifiers
      input_ids[input_ids != ""]
      input_ids
    } else if(!is.null(input$XrefBatch_identifiers)){
      # Split identifiers entered in text area by newline, comma, or space
      input_ids <- as.character(input$XrefBatch_identifiers)
      input_ids <- unlist(strsplit(input_ids, '\n|,|\\s+', perl = TRUE))
      # Remove empty strings and return the list of identifiers
      input_ids <- input_ids[input_ids != ""]
      input_ids
    } 
  })
  
  # Function to make the output table
  XrefBatch_output <- reactive({
    req(!is.null(identifiersList())) 
    if(input$type == "gene") {
      input_species <- input$inputSpecies
      input_data_source <- input$inputDataSource
      output_data_source <- input$outputDataSource
      XrefBatch_results <- Xref_function(
        identifiersList(), 
        inputSpecies = input_species, 
        inputSystemCode = input_data_source, 
        outputSystemCode = output_data_source)
      return(XrefBatch_results)
      # return(NULL)
    } else if(input$type == "metabolite") {
      input_data_source <- input$inputDataSource
      output_data_source <- input$outputDataSource
      XrefBatch_results <- Xref_function(
          identifiersList(), 
          inputSystemCode = input_data_source, 
          outputSystemCode = output_data_source)
        return(XrefBatch_results)
    }
  })
  
  # Function to clear previous outputs
  # clearPreviousOutputs <- function() {
  #   updateTextAreaInput(session, "XrefBatch_identifiers", value = "")
  #   XrefBatch_input_file(NULL) # Reset the file input
  #   # Reset file input appearance
  #   js_reset_file_input <- "$('#XrefBatch_input_file').val(null); $('.custom-file-label').html('Please upload file..');"
  #   session$sendCustomMessage(type = 'jsCode', message = js_reset_file_input)
  #   XrefBatch_mapping$XrefBatch_table <- NULL
  # }

  XrefBatch_mapping <- reactiveValues(XrefBatch_table = NULL)
  observeEvent(input$XrefBatch_get, {
    if(!is.null(XrefBatch_output())) {
      XrefBatch_mapping$XrefBatch_table <- req(
        DT::datatable(XrefBatch_output(),
                      options = list(orderClasses = TRUE,
                                     lengthMenu = c(10, 25, 50, 100),
                                     pageLength = 10)
        )
      )
    } 
  }, ignoreInit = TRUE)
  
  # Update output display
  output$XrefBatch_mapping_results <- renderDT({
    if (length(identifiersList()) != 0) {
      XrefBatch_mapping$XrefBatch_table
    } else {
      NULL
    }
  })
  
  ## Download results
  output$XrefBatch_download <- downloadHandler(
    filename = function() {
      paste0("XrefBatch_mapping_BridgeDB-Shiny.", input$XrefBatch_download_format)
    },
    content = function(file) {
      if(!is.null(XrefBatch_output())) {
        write.table(
          XrefBatch_output(), file, row.names = FALSE, 
          sep = ifelse(input$XrefBatch_download_format == "tsv", "\t", ","),
          quote = FALSE
        )
      }
    }
  )
  observe({
    if(is.null(XrefBatch_output())) {
      shinyjs::disable("XrefBatch_download")
    } else {
      shinyjs::enable("XrefBatch_download")
    }
  })
  
  # Handle clearing of input and output
  observeEvent(input$XrefBatch_clear_list, {
    updateTextAreaInput(session, "XrefBatch_identifiers", value = "")
    XrefBatch_input_file(NULL) # Reset the file input
    # Reset file input appearance
    js_reset_file_input <- "$('#XrefBatch_input_file').val(null); $('.custom-file-label').html('Please upload file..');"
    session$sendCustomMessage(type = 'jsCode', message = js_reset_file_input)
    XrefBatch_mapping$XrefBatch_table <- NULL
  })
  
  #sec2pri tab
  #Define the input options based on data source
  output$dataSource <- renderUI({
    selectInput(
      inputId = 'sec2priDataSource', 
      label = 'Choose the data source:',
      choices = c("ChEBI", "HMDB", "Wikidata", "HGNC", "HGNC Accession number"),
      selected = "ChEBI"
    )
  })
  
  # Update the TextArea based on the selected database
  observeEvent(input$sec2priDataSource, {
    updateTextAreaInput(session, "sec2pri_identifiers", value = ifelse(input$sec2priDataSource == "HGNC", "HOXA11\nHOX12\nCD31", 
                                                                       ifelse(input$sec2priDataSource == "HGNC Accession number","HGNC:24\nHGNC:32\nHGNC:13349\nHGNC:7287\n",
                                                                              ifelse(input$sec2priDataSource == "HMDB","HMDB0000005\nHMDB0004990\nHMDB60172\nHMDB00016",
                                                                                     ifelse(input$sec2priDataSource == "ChEBI", "CHEBI:20245\nCHEBI:136845\nCHEBI:656608\nCHEBI:4932",
                                                                                            ifelse(input$sec2priDataSource == "Wikidata","Q422964\nQ65174948\nQ25436441",""))))))
  })
  
  #Check the input
  seq2pri_input_file <- reactiveVal(NULL)
  observeEvent(input$sec2pri_identifiers_file, {
    if(!is.null(input$sec2pri_identifiers_file)){
      seq2pri_input_file(input$sec2pri_identifiers_file)
    }
  })
  
  #Function to make a vector for input identifiers
  secIdentifiersList <- reactive({
    if(!is.null(seq2pri_input_file())){
      print("Reading identifiers from file...")
      input_ids <- readLines(seq2pri_input_file()$datapath)
      # Remove empty or whitespace-only last line
      last_line <- input_ids[length(input_ids)]
      if(nchar(trimws(last_line)) == 0){
        input_ids <- input_ids[-length(input_ids)]
      }
      # Split identifiers on newline, comma, or space
      input_ids <- unlist(strsplit(input_ids, '\\"|\n|\t|,|\\s+', perl = TRUE))
      # Remove empty strings and return the list of identifiers
      input_ids[input_ids != ""]
      input_ids
    } else if(!is.null(input$sec2pri_identifiers)){
      # Split identifiers entered in text area by newline, comma, or space
      input_ids <- as.character(input$sec2pri_identifiers)
      input_ids <- unlist(strsplit(input_ids, '\n|,|\\s+', perl = TRUE))
      # Remove empty strings and return the list of identifiers
      input_ids <- input_ids[input_ids != ""]
      input_ids
    }
  })
  
  # Function to calculate the number of primary and secondary identifiers in the input table
  sec2pri_proportion <- reactive({
    req(input$sec2priDataSource) 
    if(!is.null(input$sec2pri_identifiers_file) | !is.null(input$sec2pri_identifiers)) {
      if(input$sec2priDataSource == "HGNC Accession number"){
        priID_list = primaryIDs_HGNC.ID
        dataset = HGNC.ID
      } else {
        priID_list = get(paste0("primaryIDs_", input$sec2priDataSource))
        dataset = get(input$sec2priDataSource)
      }
      proportion_table = data.frame(
        type = c("#input IDs", 
                 "#primary IDs",
                 "#secondary IDs", 
                 "#unknown"),
        no = c(length(unique(secIdentifiersList())),
               length(intersect(unique(secIdentifiersList()), priID_list)),
               length(intersect(unique(secIdentifiersList()), dataset$secondaryID)),
               length(unique(secIdentifiersList())) - 
                 (length(intersect(unique(secIdentifiersList()), priID_list)) +
                    length(intersect(unique(secIdentifiersList()), dataset$secondaryID)))
        )
      )# %>% mutate(prop = no/length(unique(secIdentifiersList())))
      return(proportion_table[proportion_table$no != 0, ])
    }
  })
  
  # Function to make the output table
  sec2pri_output <- reactive({
    req(input$sec2priDataSource)
    if(!is.null(input$sec2pri_identifiers_file) | !is.null(input$sec2pri_identifiers)) {
      if(input$sec2priDataSource == "HGNC Accession number"){
        dataset = HGNC.ID
      } else {
        dataset = get(input$sec2priDataSource)
      }
      if(grepl("HGNC", input$sec2priDataSource)){
        seq2pri_table_output <- dataset %>% 
          filter(secondaryID %in% c(secIdentifiersList())) %>%
          select(secondaryID, primaryID, comment) %>%
          rename(identifier = secondaryID, `primary ID` = primaryID)
      } else {
        seq2pri_table_output <- dataset %>% 
          filter(secondaryID %in% c(secIdentifiersList())) %>%
          select(secondaryID, primaryID) %>%
          rename(identifier = secondaryID, `primary ID` = primaryID)
      }
      return(seq2pri_table_output)
    }
  })
  
  # Function to clear previous outputs
  # clearPreviousSec2priOutputs <- function() {
  #   updateTextAreaInput(session, "sec2pri_identifiers", value = "")
  #   # Reset file input appearance
  #   js_reset_file_input <- "$('#sec2pri_identifiers_file').val(null); $('.custom-file-label').html('Please upload file..');"
  #   session$sendCustomMessage(type = 'jsCode', message = js_reset_file_input)
  #   seq2pri_mapping$seq2pri_pieChart <- NULL
  #   seq2pri_mapping$metadata <- NULL
  # }
  
  seq2pri_mapping <- reactiveValues(seq2pri_pieChart = NULL, metadata = NULL, seq2pri_table = NULL)
  
  observeEvent(input$sec2pri_get, {
    seq2pri_mapping$seq2pri_pieChart <- 
      # Function to draw the piechart
      ggplot(sec2pri_proportion() [c(-1), ],
             aes(x = type, y = no, fill = type)) +
        geom_col(position = position_dodge(0.9), width = 0.9) +
        scale_fill_brewer(palette = "Blues") +
        coord_flip() +
        piechart_theme + 
        ggtitle(ifelse(is.na(sec2pri_proportion()$no[1]), "No input provided",
                             paste0(sec2pri_proportion()$no[1], " (unique) input identifiers"))) +
        geom_text(aes(y = no, label = no), size = 6,
                  position = position_stack(vjust = .5)) +
        theme(plot.margin = unit(c(1, 1, -0.5, 1), "cm"))

    if(nrow(sec2pri_output()) != 0) {
      seq2pri_mapping$seq2pri_table <- req(
        DT::datatable(sec2pri_output(),
                      options = list(orderClasses = TRUE,
                                     lengthMenu = c(10, 25, 50, 100),
                                     pageLength = 10)
        )
      )
    } 
  }, ignoreInit = TRUE)
  
  # Update output display
  output$sec2pri_mapping_results <- 
    renderDT({
      if (length(secIdentifiersList()) != 0) {
        seq2pri_mapping$seq2pri_table
      } else {
        NULL
      }
    })


  
  ## Download results
  output$sec2pri_download <- downloadHandler(
    filename = function() {
      paste0("sec2pri_mapping_BridgeDB-Shiny.", input$sec2pri_download_format)
    },
    # filename = "sec2pri_mapping_BridgeDB-Shiny.csv",
    content = function(file) {
      if(!is.null(sec2pri_output())) {
        if(input$sec2priDataSource == "HGNC Accession number"){
          priID_list = primaryIDs_HGNC.ID
          dataset = HGNC.ID
        } else {
          priID_list = get(paste0("primaryIDs_", input$sec2priDataSource))
          dataset = get(input$sec2priDataSource)
        }
        primaryIDs <- intersect(unique(secIdentifiersList()), priID_list)
        unknownIDs <- unique(secIdentifiersList())[!unique(secIdentifiersList()) %in%
                                                     c(priID_list, dataset$secondaryID)]
        if(grepl("HGNC", input$sec2priDataSource)){
          output <- rbind(
            sec2pri_output(),
            data.frame(identifier = primaryIDs,
                       `primary ID` = primaryIDs,
                       comment = rep("", length(primaryIDs)), check.names = FALSE),
            data.frame(identifier = unknownIDs,
                       `primary ID` = rep("", length(unknownIDs)),
                       comment = rep("Unknown", length(unknownIDs)), check.names = FALSE)
            
          )
        } else {
          output <- rbind(
            sec2pri_output(),
            data.frame(identifier = primaryIDs,`primary ID` = primaryIDs, check.names = FALSE),
            data.frame(identifier = unknownIDs,`primary ID` = rep(NA, length(unknownIDs)), check.names = FALSE)
          ) %>%
            mutate(comment = ifelse(identifier %in% unknownIDs, "Unknown", ""))
        }
        
        write.table(
          output, file, row.names = FALSE, 
          sep = ifelse(input$sec2pri_download_format == "tsv", "\t", ","),
          quote = FALSE
        )
      }
    }
  )
  
  observe({
    if(nrow(sec2pri_output()) == 0) {
      shinyjs::disable("sec2pri_download")
    } else {
      shinyjs::enable("sec2pri_download")
    }
  })
  

  output$sec2pri_piechart_results <- renderPlot({
    seq2pri_mapping$seq2pri_pieChart
  },  height = 200, width = 400)
  
  observeEvent(input$sec2pri_get, {
    output$sec2pri_metadata <-  
      if(grepl("HGNC", input$sec2priDataSource) & nrow(sec2pri_output()) != 0){
        renderText(HTML("The data was obtained from the <a href='https://ftp.ebi.ac.uk/pub/databases/genenames/hgnc/archive/monthly/tsv/' target='_blank'>HGNC database</a> in its monthly release of <b>June 2023</b>."))
      } else if (grepl("HMDB", input$sec2priDataSource) & nrow(sec2pri_output()) != 0){
        renderText(HTML("The data was obtained from the <a href='https://hmdb.ca/downloads' target='_blank'>HMDB database</a> (version 5.0) released on <b>November 2021</b>."))
      } else if (grepl("ChEBI", input$sec2priDataSource) & nrow(sec2pri_output()) != 0){
        renderText(HTML("The data was obtained from the <a href='https://ftp.ebi.ac.uk/pub/databases/chebi/archive/rel211/SDF/' target='_blank'>ChEBI database</a> (rel211) released on <b>June 2022</b>."))
      } else if (grepl("Wikidata", input$sec2priDataSource) & nrow(sec2pri_output()) != 0){
        renderText(HTML("The data was obtained from the <a href='https://query.wikidata.org/' target='_blank'>Wikidata database</a> on <b>July 30, 2022</b>."))
      } 
  })
  
  # Handle clearing of input and output
  observeEvent(input$sec2pri_clear_list, {
    updateTextAreaInput(session, "sec2pri_identifiers", value = "")
    # Reset file input appearance
    seq2pri_input_file(NULL) # Reset the file input
    js_reset_file_input <- "$('#sec2pri_identifiers_file').val(null); $('.custom-file-label').html('Please upload file..');"
    session$sendCustomMessage(type = 'jsCode', message = js_reset_file_input)
    seq2pri_mapping$seq2pri_pieChart <- NULL
    seq2pri_mapping$metadata <- NULL
    seq2pri_mapping$seq2pri_table <- NULL
  })
  
  # add BridgeDb logo (in the text)
  output$bridgeDb_logo <- renderImage({
    list(src = "www/logo_BridgeDb.png",
         width = "120px",
         height = "70px")
  }, deleteFile = F)
  
  # add BridgeDb logo (page footer)
  output$bridgeDb_logo_wide <- renderImage({
    list(src = "www/logo_BridgeDb_footer.png",
         width = "100%",
         height = "auto")
  }, deleteFile = F)
  
}

shinyApp(ui = ui, server = server)

