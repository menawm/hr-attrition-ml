
knitr::opts_chunk$set(echo = TRUE)
library(class)
library(caret)
library(ggplot2)
library(scales)
library(knitr)
library(kableExtra)
library(dplyr)
library(rpart)
library(rpart.plot)
library(corrplot)





hr <- read.csv("../data/hrdata.csv")


#remove unnecessary columns
hr$X <- NULL


#rename sales column to dept
hr$dept <- hr$sales
hr$sales <- NULL


#convert categorical variables to factors

hr$salary <- as.factor(hr$salary)
hr$dept <- as.factor(hr$dept)



str(hr)

#View summary statistics
summary(hr)

colSums(is.na(hr))




#model.matrix() creates dummy variables for factors
hr_dummies <- as.data.frame(model.matrix(~ . -1, data = hr))

# View the structure
str(hr_dummies)


#Min-Max scaling function
minmax <- function(x) {
  (x - min(x)) / (max(x) - min(x))
}

#Apply to all columns
hr_norm <- as.data.frame(lapply(hr_dummies, minmax))

# View summary to confirm values are between 0 and 1
summary(hr_norm)

#split the data
set.seed(12345)  # for reproducibility (so you get the same split each time)



#Pick 30% of rows randomly for testing
test_rows <- sample(1:nrow(hr_norm), 0.3 * nrow(hr_norm))

#Split into training and test sets
hr_test <- hr_norm[test_rows, ]
hr_train <- hr_norm[-test_rows, ]

#Save the target variable (left) separately for both sets
hr_test_y <- hr_test$left
hr_train_y <- hr_train$left

#Remove 'left' column from features (because we already saved it)
hr_test$left <- NULL
hr_train$left <- NULL



#check data
nrow(hr_train)  # should be about 70% of the total 
nrow(hr_test)   # should be about 30% of the total 

head(hr_train_y)  # target variable 
head(hr_train)    # feature columns 


## LR Model
```{r build lr, echo=TRUE}
# --- Prepare data (attach target properly) ---
hr_train_lr <- hr_train
hr_train_lr$Attrition <- hr_train_y

hr_test_lr <- hr_test
hr_test_lr$Attrition <- hr_test_y

# --- Train Logistic Regression ---
lr_model <- glm(Attrition ~ ., data = hr_train_lr, family = "binomial")

# --- Predict probabilities ---
lr_probs <- predict(lr_model, newdata = hr_test_lr, type = "response")

# --- Convert probabilities to class labels (threshold = 0.3 for better recall) ---
lr_pred <- ifelse(lr_probs > 0.3, 1, 0)

# --- Confusion Matrix ---
conf_matrix <- table(Predicted = lr_pred, Actual = hr_test_lr$Attrition)
knitr::kable(conf_matrix, caption = "Confusion Matrix")


# LR Evaluation Metrics 
accuracy <- mean(lr_pred == hr_test_lr$Attrition)

sensitivity <- sum(lr_pred == 1 & hr_test_lr$Attrition == 1) / 
  sum(hr_test_lr$Attrition == 1)

precision <- sum(lr_pred == 1 & hr_test_lr$Attrition == 1) / 
  sum(lr_pred == 1)

metrics <- data.frame(
  Metric = c("Accuracy", "Sensitivity", "Precision"),
  Value = c(accuracy, sensitivity, precision)
)

knitr::kable(metrics, digits = 3, caption = "Model Performance Metrics")


# --- Logistic Regression Coefficients ---
lr_coefficients <- summary(lr_model)$coefficients

knitr::kable(
  round(lr_coefficients, 3),
  caption = "Logistic Regression Coefficients"
)
# --- Odds Ratios (VERY important for interpretation) ---
odds_ratios <- exp(coef(lr_model))

odds_table <- data.frame(
  Feature = names(odds_ratios),
  Odds_Ratio = round(odds_ratios, 3)
)

knitr::kable(odds_table, caption = "Odds Ratios (Interpretation)")
# --- Clean Feature Importance Table ---
lr_feature_table <- data.frame(
  Feature = names(coef(lr_model)),
  Coefficient = coef(lr_model),
  Odds_Ratio = exp(coef(lr_model))
)

# Sort by impact
lr_feature_table <- lr_feature_table[
  order(abs(lr_feature_table$Coefficient), decreasing = TRUE),
]

knitr::kable(
  lr_feature_table,
  digits = 3,
  caption = "Feature Importance (Sorted by Impact)"
)






# Select numeric features
numeric_data <- hr_train[, sapply(hr_train, is.numeric)]

# Correlation matrix
cor_matrix <- cor(numeric_data, use = "complete.obs")

corrplot(
  cor_matrix,
  method = "square",
  type = "upper",
  diag = TRUE,
  tl.col = "black",
  tl.cex = 0.8,
  tl.srt = 45,
  addCoef.col = NULL,   # remove numbers
  addgrid.col = "grey70",
  cl.cex = 0.8,
  mar = c(0, 0, 2, 0),
  col = colorRampPalette(c("#B2182B", "#F7F7F7", "#2166AC"))(200),
  title = "Feature Correlation Heatmap (All Variables)"
)


## DT
# Create training and test data frames with target variable
hr_train_df <- data.frame(hr_train)
hr_train_df$left <- as.factor(hr_train_y)

hr_test_df <- data.frame(hr_test)
hr_test_df$left <- as.factor(hr_test_y)

# Train decision tree model
tree_model <- rpart(
  left ~ .,
  data = hr_train_df,
  method = "class",
  control = rpart.control(cp = 0.01)
)



#plot dt
rpart.plot(tree_model)


# Predict probabilities on test data
tree_probs <- predict(tree_model, newdata = hr_test_df, type = "prob")

# Probability of leaving = column 2
tree_probs <- tree_probs[, 2]

# Convert probabilities to class labels using 0.5 threshold
tree_pred <- ifelse(tree_probs > 0.5, 1, 0)


# Confusion matrix
conf_matrix_tree <- table(Predicted = tree_pred, Actual = hr_test_y)

conf_df <- as.data.frame.matrix(conf_matrix_tree)
colnames(conf_df) <- c("Actual: 0 (Stayed)", "Actual: 1 (Left)")
conf_df <- cbind(Predicted = rownames(conf_df), conf_df)
rownames(conf_df) <- NULL

kable(conf_df, caption = "Decision Tree Confusion Matrix") %>%
  kable_styling(full_width = FALSE, bootstrap_options = c("striped", "hover", "condensed"))

# Metrics
tree_accuracy <- mean(tree_pred == hr_test_y)
tree_sensitivity <- sum(tree_pred == 1 & hr_test_y == 1) / sum(hr_test_y == 1)
tree_precision <- sum(tree_pred == 1 & hr_test_y == 1) / sum(tree_pred == 1)

metrics_df <- data.frame(
  Metric = c("Accuracy", "Recall (Sensitivity)", "Precision"),
  Value = round(c(tree_accuracy, tree_sensitivity, tree_precision), 3)
)

kable(metrics_df, caption = "Decision Tree Performance Metrics") %>%
  kable_styling(full_width = FALSE, bootstrap_options = c("striped", "hover", "condensed"))


#Run KNN 
knn_pred <- knn(train = hr_train,    # training data
                test = hr_test,      # testing data
                cl = hr_train_y,     # training labels (left column)
                k = 21)              # number of neighbors

#Check prediction output
summary(knn_pred)
```

# Step 6: Evaluate the Model
```{r evaluate knn, echo=TRUE}

# Generate the confusion matrix
confusionMatrix(as.factor(knn_pred), 
                as.factor(hr_test_y), 
                positive = "1")




# Assumptions
total_employees <- 14999
attrition_rate <- 0.24
turnover_cost <- 20000



#baseline costs for no interventions 
total_leavers <- total_employees * attrition_rate
baseline_cost <- total_leavers * turnover_cost
baseline_cost

ggplot(data.frame(Scenario = "No Intervention", Cost = baseline_cost), 
       aes(x = Scenario, y = Cost)) +
  geom_bar(stat = "identity", fill = "#00274C", width = 0.5) +
  
  geom_text(
    aes(label = scales::dollar(Cost)),
    vjust = -0.6,
    size = 5,
    fontface = "bold"
  ) +
  
  labs(
    title = "Baseline Cost of Employee Attrition",
    subtitle = "Estimated annual cost if no intervention is implemented",
    x = "",
    y = "Total Cost ($)"
  ) +
  
  scale_y_continuous(
    labels = scales::dollar_format(),
    expand = expansion(mult = c(0, 0.1))  # adds space above bar
  ) +
  
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 12),
    axis.text.x = element_text(size = 11),
    axis.text.y = element_text(size = 10),
    panel.grid.major.x = element_blank()
  )





# Decision tree model performance
sensitivity <- 0.9159
precision <- 0.9607

# Expected leavers per year
leavers_per_year <- total_employees * attrition_rate

# Employees correctly identified by the model
identified_leavers <- leavers_per_year * sensitivity

# Total employees flagged for intervention
adjusted_intervention_count <- identified_leavers / precision

# Recognition Program assumptions
recog_cost <- 500
recog_success <- 0.15

# Career Development Program assumptions
career_cost <- 1000
career_success <- 0.25

# Recognition Program calculations
recog_retained <- identified_leavers * recog_success
recog_savings <- recog_retained * turnover_cost
recog_total_cost <- adjusted_intervention_count * recog_cost
recog_net_savings <- recog_savings - recog_total_cost
recog_roi <- (recog_net_savings / recog_total_cost) * 100

# Career Development Program calculations
career_retained <- identified_leavers * career_success
career_savings <- career_retained * turnover_cost
career_total_cost <- adjusted_intervention_count * career_cost
career_net_savings <- career_savings - career_total_cost
career_roi <- (career_net_savings / career_total_cost) * 100

# Create results table
results <- data.frame(
  Initiative = c("Recognition Program", "Career Development Program"),
  Retained_Employees = round(c(recog_retained, career_retained)),
  Adjusted_Intervention_Count = round(c(adjusted_intervention_count, adjusted_intervention_count)),
  Cost_per_Intervention = c(recog_cost, career_cost),
  Total_Intervention_Cost = round(c(recog_total_cost, career_total_cost), 2),
  Savings_from_Retention = round(c(recog_savings, career_savings), 2),
  Net_Savings = round(c(recog_net_savings, career_net_savings), 2),
  ROI = round(c(recog_roi, career_roi), 1)
)

results



results[, c("Initiative", "Net_Savings", "ROI")]



#display dt net impact plot
ggplot(results, aes(x = Initiative, y = Net_Savings, fill = Initiative)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = scales::dollar(Net_Savings)), vjust = -0.5) +
  scale_fill_manual(values = c("#FFCB05", "#00274C")) +
  labs(
    title = "Net Financial Impact by Initiative",
    x = "Initiative",
    y = "Net Savings ($)"
  ) +
  scale_y_continuous(labels = scales::dollar_format()) +
  theme_minimal() +
  theme(
    legend.position = "none",
    plot.title = element_text(face = "bold", size = 14),
    axis.text = element_text(size = 11)
  )

#display dt roi plot
results <- data.frame(
  Initiative = c("Recognition Program", "Career Development Program"),
  Retained_Employees = round(c(recog_retained, career_retained)),
  Adjusted_Intervention_Count = round(c(adjusted_intervention_count, adjusted_intervention_count)),
  Cost_per_Intervention = c(recog_cost, career_cost),
  Total_Intervention_Cost = round(c(recog_total_cost, career_total_cost), 2),
  Savings_from_Retention = round(c(recog_savings, career_savings), 2),
  Net_Savings = round(c(recog_net_savings, career_net_savings), 2),
  ROI = round(c(recog_roi, career_roi), 1)   # ← THIS LINE IS CRITICAL
)


ggplot(results, aes(x = Initiative, y = ROI, fill = Initiative)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = c("#FFCB05", "#00274C")) +
  labs(
    title = "Return on Investment (ROI) by Initiative",
    x = "Initiative",
    y = "ROI (%)"
  ) +
  theme_minimal() +
  theme(
    legend.position = "none",
    plot.title = element_text(face = "bold", size = 14),
    axis.text = element_text(size = 11)
  )



#r baseline_vs_interventions

# Create comparison dataset (MUST be inside this chunk or above it)
comparison <- data.frame(
  Scenario = c("No Intervention", results$Initiative),
  Cost = c(
    baseline_cost,
    baseline_cost - results$Net_Savings
  )
)

# Plot
ggplot(comparison, aes(x = Scenario, y = Cost, fill = Scenario)) +
  geom_bar(stat = "identity", width = 0.6) +
  
  geom_text(
    aes(label = scales::dollar(Cost)),
    vjust = -0.6,
    size = 4.5,
    fontface = "bold"
  ) +
  
  scale_fill_manual(values = c(
    "No Intervention" = "#7A7A7A",
    "Recognition Program" = "#FFCB05",
    "Career Development Program" = "#00274C"
  )) +
  
  labs(
    title = "Total Cost Comparison: No Intervention vs HR Strategies",
    subtitle = "Impact of targeted retention strategies on attrition cost",
    x = "Scenario",
    y = "Total Cost ($)"
  ) +
  
  scale_y_continuous(
    labels = scales::dollar_format(),
    expand = expansion(mult = c(0, 0.1))
  ) +
  
  theme_minimal() +
  theme(
    legend.position = "none",
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11),
    axis.text = element_text(size = 10),
    panel.grid.major.x = element_blank()
  )




# --- Base numbers ---
total_employees <- 14999
attrition_rate <- 0.24
turnover_cost <- 20000

# Decision Tree performance
sensitivity <- 0.9159
precision <- 0.9607

# Total leavers
total_leavers <- total_employees * attrition_rate

# Identified leavers
identified_leavers <- total_leavers * sensitivity

# Missed leavers
missed_leavers <- total_leavers - identified_leavers

# Total interventions (includes false positives)
total_flagged <- identified_leavers / precision

# --- Program assumptions ---
recog_success <- 0.25
career_success <- 0.35

# --- FAILED INTERVENTIONS ---
recog_failed <- identified_leavers * (1 - recog_success)
career_failed <- identified_leavers * (1 - career_success)

# --- COSTS ---
missed_cost <- missed_leavers * turnover_cost

recog_failed_cost <- recog_failed * turnover_cost
career_failed_cost <- career_failed * turnover_cost

# --- SUMMARY TABLE ---
failure_results <- data.frame(
  Category = c("Missed Leavers", "Failed - Recognition", "Failed - Career"),
  Employees = round(c(missed_leavers, recog_failed, career_failed)),
  Cost = round(c(missed_cost, recog_failed_cost, career_failed_cost), 2)
)

failure_results


#dt_failure_plot

ggplot(failure_results, aes(x = Category, y = Cost, fill = Category)) +
  geom_bar(stat = "identity", width = 0.6) +
  
  geom_text(
    aes(label = scales::dollar(Cost)),
    vjust = -0.6,
    size = 4.5,
    fontface = "bold"
  ) +
  
  scale_fill_manual(values = c(
    "Missed Leavers" = "#7A7A7A",      # gray (model failure)
    "Failed - Recognition" = "#FFCB05", # maize
    "Failed - Career" = "#00274C"       # blue
  )) +
  
  labs(
    title = "Breakdown of Remaining Attrition Costs",
    subtitle = "Where turnover costs persist despite predictive modeling and interventions",
    x = "Category",
    y = "Cost ($)"
  ) +
  
  scale_y_continuous(
    labels = scales::dollar_format(),
    expand = expansion(mult = c(0, 0.1))
  ) +
  
  theme_minimal() +
  theme(
    legend.position = "none",
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11),
    axis.text = element_text(size = 10),
    panel.grid.major.x = element_blank()
  )














