# Synthetic Bank Customer Segmentation Dataset

This dataset was generated specifically for the GitHub portfolio project
**Bank Customer Segmentation & Behavioral Analysis**.

## Tables

- `customers.csv` — 20,000 customers
- `accounts.csv` — 24,915 accounts
- `transactions.csv` — 963,485 transactions
- `regions.csv` — 10 regions

## Period

Transactions cover approximately 2022–2025.

## Important

The data is entirely synthetic. It does not represent real customers,
accounts, transactions, or any real financial institution.

The generator intentionally creates heterogeneous customer behavior,
including:

- different customer value levels,
- active customers,
- dormant accounts,
- closed accounts,
- multiple account types,
- seasonal transaction patterns,
- regional differences,
- different transaction types.

## Suggested analytical metrics

Distinguish between:

- gross transaction volume: `SUM(ABS(amount))`
- net cash flow: `SUM(amount)`
- transaction frequency: transaction count
- average transaction value
- activity over time

The values are designed for analytical practice rather than for
statistical inference about real banking populations.


### EDA Findings

The exploratory data analysis confirmed that the dataset is structurally consistent and suitable for further analysis.

Key findings:

- Primary keys are unique across all tables.
- Referential integrity between customers, accounts, transactions, and regions is preserved.
- No missing values were identified in the analysed tables.
- 342 accounts have no recorded transactions.
- Among these accounts, 56 are labelled as active, 33 as dormant, and 253 as closed.
- This creates potential inconsistencies between account status labels and observed transaction history.

#### Open Questions and Data Limitations

Several observations identified during the exploratory phase required additional consideration during the analysis:

- The dataset does not provide a clear reference date, limiting the ability to fully validate some account statuses.
- The expected relationship between account types and transaction types is not documented.
- Certain combinations of account and transaction types may require additional business context for interpretation.
- Account status labels cannot always be assumed to reflect observed transactional behaviour and were therefore validated separately throughout the project.

## Key Findings

The analysis identified substantial differences between customer groups, regions, and activity patterns.

- 7,188 customers (35.9%) were active within the last 30 days, while 4,099 customers (20.5%) met the dormancy definition of no transactions within 180 days.
- 2,336 customers (11.7%) showed declining activity between Q3 and Q4 2025.
- The highest-value customer quartile generated over 7.4 million in transaction volume, compared to only 0.22 million in the lowest-value quartile.
- Customers in the highest-value quartile completed more than 130,000 transactions, compared to fewer than 8,000 transactions in the lowest-value quartile.
- Metro was the largest region, representing 18.8% of all customers and nearly 20% of total transaction volume.
- Behavioural segmentation produced overlapping customer groups and left part of the population unclassified, leading to the selection of customer value quartiles as the final segmentation approach for comparative analysis.

## Limitations and Lessons Learned

Real-world analytical projects rarely start with perfectly documented and complete datasets. During the data quality assessment, several limitations were identified that influenced the scope and interpretation of the analysis.

| ID | Limitation | Impact | Mitigation | Lesson Learned |
|----|------------|---------|------------|----------------|
| L-001 | Account closure date is not available in the dataset. | Account lifecycle analysis cannot be performed. Transactions occurring after account closure cannot be verified. | Restrict analyses to the current account status only. | Not all business questions can be answered when key historical attributes are missing. |
| L-002 | 28.38% of transactions occurred before the recorded account open date. | The `open_date` field cannot be reliably interpreted as the beginning of the account lifecycle. Analyses based on account age may therefore be biased. | Avoid using `open_date` as a strict validity boundary without additional validation. | Column names do not necessarily reflect the true business meaning of a field. |
| L-003 | The business meaning of account statuses (`active`, `dormant`, `closed`) is not documented. | Analytical definitions may differ from the definitions used by the source organization. | Explicitly distinguish analytical rules from source-system labels. | Metadata and business definitions are as important as the data itself. |
| L-004 | The Metro region is substantially larger than other regions in terms of population. | Absolute metrics may overstate regional performance. | Use normalized metrics such as customers per capita, transaction volume per capita, and customers per branch. | Relative performance often provides more meaningful insights than absolute values. |
| L-005 | A large number of transaction amounts are identified as statistical outliers using the IQR rule. | Statistical outliers may influence aggregate metrics but do not necessarily indicate data quality issues. | Retain the observations and evaluate their impact on analytical results. | Statistical outliers and business anomalies are not the same concept. |
| L-006 | The project specification and the available dataset are not fully aligned. | Some planned data quality checks and analyses cannot be performed exactly as originally designed. | Document all deviations and adjust analytical goals to the available data. | Analytical projects often require adapting the scope to actual data availability. |
| L-007 | Account status and transactional behaviour are not fully aligned. | Some accounts labelled as `active` have no recorded transactions, creating potential inconsistencies between operational status labels and observed customer behaviour. | Activity-based analyses may produce conclusions that conflict with system-defined account statuses. | Use transaction history as the primary source for analytical activity definitions and clearly distinguish analytical metrics from system status labels. | Operational status fields and analytical definitions may represent different business concepts. |
| L-008 | Customer value is not explicitly defined in the project specification or the dataset documentation. | Different reasonable definitions of customer value may lead to different customer rankings and segment assignments. | Multiple value metrics were explored, including transaction volume, transaction frequency, net cash flow, and a composite Value-Activity Score. Final analyses explicitly state which definition is being used. | Business concepts should be formally defined before analytical implementation begins. |
| L-009 | System-defined dormancy differs substantially from transaction-based dormancy. | Analyses using the account status field may produce different results than analyses based on observed account activity. | Both dormancy definitions were evaluated separately and compared. | Operational status labels should not be assumed to represent behavioural activity without validation. |

### Key Takeaway

Rather than artificially correcting or inferring missing information, this project prioritizes transparency. When data limitations were identified, they were documented and incorporated into the interpretation of results. This reflects a common real-world analytical practice, where understanding the limitations of a dataset is often as important as performing the analysis itself.

#### Alternative Metric Definition

The project specification used the terms customer value and customer activity without fully defining how they should be combined. An exploratory Customer Value-Activity Score was developed using average monthly transaction frequency and average monthly gross transaction volume.

Both metrics were centred by their medians and scaled by their interquartile ranges before being combined with equal weights. The resulting score was retained as an exploratory metric rather than used in the final segmentation because its interpretation depends on business-specific assumptions about transaction types, metric weights, and the economic meaning of transaction volume. The exercise nevertheless documents how ambiguous business concepts can be translated into measurable alternatives and evaluated before a final methodology is selected.

## Customer Behaviour Analysis

### 9.1 Customer Value

Customer value was analysed using transaction-based metrics aggregated at the customer level. The analysis revealed a highly concentrated distribution of customer value, with a relatively small proportion of customers generating a disproportionately large share of total transaction activity. This concentration later served as the basis for customer value quartiles used throughout the comparative analyses.

### 9.2 Customer Value Segmentation

Customers were segmented into value quartiles to distinguish high-value and low-value groups. The segmentation revealed substantial behavioural differences between customer groups. The highest-value quartile generated more than 7.4 million in transaction volume and completed over 130,000 transactions, while the lowest-value quartile generated approximately 0.22 million in volume and fewer than 8,000 transactions. These differences confirmed that customer value quartiles provide meaningful separation for comparative analysis.

### 9.3 Dormant Accounts

The analysis compared two dormancy definitions:

- **System dormancy** based on the account status field.
- **Analytical dormancy** defined as no transaction activity during the previous 180 days.

The comparison revealed significant discrepancies between both approaches. A considerable proportion of system\-defined dormant accounts recorded recent transaction activity, while many analytically dormant accounts were not labelled as dormant by the source system.

This finding suggests that the account status field reflects additional business rules and should not be treated as a direct indicator of transaction inactivity without further validation.

### 9.4 Active Customers

A customer was considered active if at least one transaction was recorded during the previous 30 days.

The analysis identified 7,188 active customers and 7,919 active accounts. The supplemental breakdown by account status further confirmed that account status labels do not perfectly correspond to observed customer behaviour.

### 9.5 Activity Trends

The active customer population remained relatively stable between 2022 and 2024, fluctuating around 8,300–8,500 customers per month. A noticeable decline occurred during the second half of 2025, falling from 8,000 active customers in June 2025 to 7,188 in December 2025. The three-month rolling average also declined from 8,132 active customers in June 2025 to 7,189 by the end of the year, indicating a sustained reduction in customer activity rather than a temporary monthly fluctuation.

### 9.6 Declining Customers

The analysis identified 2,336 declining customers, representing 11.68% of the entire customer base and 14.08% of eligible customers. On average, these customers reduced their monthly transaction activity from 2 transactions per month during Q3 2025 to 1 transaction per month during Q4 2025. The most severe cases experienced a complete loss of activity, while the largest absolute decline observed was seven transactions per month.

### 9.7 Regional Performance

Metro was the dominant region by customer count, transaction volume, and transaction activity, accounting for approximately 18.8% of all customers and 19.8% of total transaction volume. However, normalized regional indicators revealed that East, West, and North performed more strongly when adjusted for population and branch coverage. This demonstrates the importance of evaluating both absolute and normalized performance metrics when comparing regional operations.

### Behavioural Segmentation Audit

The behavioural segments developed in Section 6 were evaluated before being used for the final segment comparison. The audit was performed at the customer level and incorporated findings from the subsequent activity and dormancy analyses.

The original segment definitions primarily used active accounts. However, later analysis showed that the system-defined dormant status did not consistently represent transaction inactivity. For this reason, the audit included both active and dormant accounts where appropriate and relied primarily on observed transaction behaviour.

Two definitions of declining activity were retained for different analytical purposes:

- The six-month declining activity attribute compares average monthly transaction activity in Q3 and Q4 2025.
- The High-Value Low-Activity segment uses the slope of monthly transaction activity to identify a broader declining trend.

The segment overlap audit showed that:

- 9,680 customers, or 48.4% of the customer base, belonged to exactly one behavioural segment.
- 3,500 customers, or 17.5%, belonged to two or more segments.
- 6,820 customers, or 34.1%, were not assigned to any behavioural segment.

These results demonstrate that the behavioural segments provide useful descriptive labels but do not form a mutually exclusive and collectively exhaustive customer classification. Therefore, customer value quartiles were selected for the final comparison in Section 9.9 because they provide clearly separated groups for comparative analysis.

The repeated SQL logic in the audit file was intentionally retained to preserve the traceability of the analytical process. In a production environment, the shared transformations would be consolidated into reusable views, temporary tables, or data-model layers to improve maintainability.

## Final Segment Selection

Based on the segmentation audit, customer value quartiles were selected as the primary framework for comparative analysis. Unlike behavioural segments, quartiles provide complete customer coverage, mutually exclusive groups, and straightforward interpretation. All subsequent comparisons therefore use customer value quartiles as the final segmentation framework.

### Business Recommendations

The results suggest several potential business actions:

- Prioritize retention efforts for High-Value Low-Activity customers, as they combine historically high value with declining engagement.
- Monitor customer activity trends regularly to identify early signs of disengagement.
- Use customer value quartiles as the primary framework for portfolio monitoring and customer comparison.
- Evaluate regional performance using normalized indicators rather than absolute transaction volumes alone.
- Validate operational account status labels against observed transaction behaviour before using them for business reporting.