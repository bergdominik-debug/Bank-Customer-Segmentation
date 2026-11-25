# Bank Customer Segmentation & Behavioral Analysis

## 1. Přehled projektu

### Cíl

Cílem projektu je vytvořit SQL-ově orientovanou analytickou případovou studii z prostředí bankovnictví. Projekt bude analyzovat zákazníky, jejich účty a transakční chování a následně zákazníky rozdělovat podle hodnoty, aktivity a engagementu.

Projekt má demonstrovat především:

- práci s relačním datovým modelem,
- SQL JOINy a agregace,
- CTE,
- window functions,
- ranking a percentily,
- časovou analýzu,
- tvorbu analytických metrik,
- interpretaci výsledků z pohledu businessu.

Hlavní těžiště projektu bude v SQL. Python/notebook bude sloužit především k EDA, validaci dat a jednoduché vizualizaci.

---

## 2. Business kontext

Banka potřebuje lépe porozumět tomu:

1. Kteří zákazníci mají nejvyšší hodnotu?
2. Kteří zákazníci jsou aktivní a kteří postupně přestávají využívat služby?
3. Jak velká je dormantní část zákaznické základny?
4. Jak se liší transakční chování jednotlivých zákaznických segmentů?
5. Které regiony vykazují nejvyšší zákaznickou aktivitu?
6. Které regiony jsou nadprůměrné i po zohlednění velikosti populace?
7. Jak se zákaznická aktivita mění v čase?

SQL dotazy proto nebudou samoúčelnou ukázkou syntaxe. Každá významnější analýza má odpovídat konkrétní business otázce.

---

## 3. Datový model

Projekt bude pracovat s relačním modelem:

```text
customers
    |
    | 1:N
    v
accounts
    |
    | 1:N
    v
transactions

regions
    |
    | 1:N
    v
customers
```

### `customers`

| Sloupec | Význam |
|---|---|
| customer_id | Primární klíč zákazníka |
| name | Jméno zákazníka / syntetický identifikátor |
| age | Věk |
| region | Region zákazníka |
| join_date | Datum vstupu do banky |
| income_band | Příjmové pásmo: low / medium / high |

### `accounts`

| Sloupec | Význam |
|---|---|
| account_id | Primární klíč účtu |
| customer_id | Vazba na zákazníka |
| account_type | checking / savings / credit |
| open_date | Datum otevření účtu |
| status | active / dormant / closed |

### `transactions`

| Sloupec | Význam |
|---|---|
| transaction_id | Primární klíč transakce |
| account_id | Vazba na účet |
| date | Datum transakce |
| amount | Hodnota transakce |
| transaction_type | deposit / withdrawal / payment / transfer |

### `regions`

| Sloupec | Význam |
|---|---|
| region | Primární klíč regionu |
| population | Populace regionu |
| branch_count | Počet poboček |

---

## 4. Zdroj dat

### Doporučená varianta: vlastní syntetická data

Pro portfolio bude preferována vlastní syntetická relační databáze. Důvodem je možnost kontrolovat:

- velikost jednotlivých tabulek,
- vztahy mezi zákazníky, účty a transakcemi,
- podíl aktivních a dormantních klientů,
- rozložení zákaznické hodnoty,
- regionální rozdíly,
- časové trendy,
- sezónnost.

Doporučený řád velikosti datasetu:

- 20 000 zákazníků,
- 30 000 účtů,
- přibližně 1 000 000 transakcí,
- 30–50 regionů.

Data mají být syntetická a v README musí být jasně uvedeno, že nejde o skutečná bankovní data.

---

## 5. Definice metrik

Je důležité předem přesně definovat význam analytických metrik.

### Transaction volume

Celkový objem transakcí.

U transakcí, kde `amount` obsahuje kladné a záporné hodnoty, je vhodné rozlišovat:

```sql
SUM(ABS(amount))
```

jako gross transaction volume, obrat

a

```sql
SUM(amount)
```

jako net cash flow, rozdíl mezi příchozími a odchozími transakcemi.

Tyto dvě metriky nesmí být zaměňovány.

### Transaction frequency

Počet transakcí zákazníka za určité období.

### Average transaction value

Průměrná hodnota transakce.

### Customer activity

Kombinace frekvence transakcí a jejich objemu.

### Dormancy

Zákazník nebo účet bez transakce po definované období.

Výchozí pravidlo:

- dormant = žádná transakce alespoň 180 dní,
- active = alespoň jedna transakce během posledních 30 dní.

Tyto prahy jsou analytická pravidla vytvořená pro projekt, nikoliv skutečná bankovní politika.

---

## 6. Segmentace zákazníků

Segmentace bude založena především na kombinaci **customer value** a **customer activity**.

### 6.1 High-value active

Zákazník s vysokým transaction volume a zároveň vysokou aktivitou.

Preferovaná definice:

- top 10 % zákazníků podle relevantní hodnotové metriky,
- zároveň aktivní v posledním sledovaném období.

### 6.2 High-value low-activity

Zákazník s vysokou historickou hodnotou, ale současně nízkou nebo klesající aktivitou.

Tento segment je důležitý zejména z pohledu retention, protože může představovat zákazníky s potenciálně vysokou hodnotou, kteří začínají odcházet.

### 6.3 Active mass customers

Aktivní zákazníci se standardní úrovní hodnoty a engagementu.

### 6.4 Low-value / low-engagement

Zákazníci s nízkým transaction volume a nízkou aktivitou.

### 6.5 Dormant

Zákazníci nebo účty bez transakce po dobu alespoň 180 dní.

---

## 7. Časová analýza

Projekt nebude analyzovat pouze aktuální stav. Důležitou součástí bude sledování změn v čase.

Například:

- monthly active customers,
- monthly transaction volume,
- monthly transaction frequency,
- vývoj dormant customer base,
- vývoj jednotlivých segmentů,
- zákazníci s výrazným poklesem aktivity.

Hlavní otázka:

> Is customer engagement improving or deteriorating over time?

Důraz bude kladen na změnu chování, nikoliv pouze na snapshot aktuálního stavu.

---

## 8. Regionální analýza

Pro každý region budou sledovány například:

- počet zákazníků,
- počet transakcí,
- transaction volume,
- transakce na zákazníka,
- transaction volume na zákazníka,
- zákazníci na pobočku,
- transaction volume na 1 000 obyvatel.

Díky `population` a `branch_count` nebude analýza založena pouze na absolutních číslech.

Například region s největším transaction volume nemusí být zároveň regionem s nejvyšší relativní aktivitou.

---

## 9. SQL analytické úlohy

### 9.1 Customer value

Identifikovat zákazníky s nejvyšším průměrným měsíčním transaction volume.

Použít:

- CTE,
- `DATE_TRUNC`,
- agregace,
- `HAVING`.

### 9.2 Customer value quartiles / percentiles

Rozdělit zákazníky podle hodnoty do kvartilů nebo percentilů.

Použít:

- `NTILE()`,
- window functions.

### 9.3 Dormant accounts

Identifikovat účty bez transakce alespoň 180 dní.

Použít:

- `LEFT JOIN`,
- `MAX(date)`,
- date functions,
- práci s `NULL`.

### 9.4 Active customers

Identifikovat zákazníky s alespoň jednou transakcí v posledních 30 dnech.

### 9.5 Activity trend

Spočítat měsíční počet aktivních zákazníků a sledovat jeho vývoj.

### 9.6 Declining customers

Identifikovat zákazníky, jejichž aktivita v posledních měsících výrazně poklesla.

Možné využití:

- `LAG()`,
- rolling averages,
- porovnání aktuálního a předchozího období.

### 9.7 Region performance

Porovnat regiony podle:

- customer count,
- transaction count,
- transaction volume,
- activity per customer.

Použít:

- agregace,
- `RANK()`.

### 9.8 Normalized regional performance

Porovnat regiony po zohlednění:

- population,
- branch count.

### 9.9 Segment comparison

Porovnat jednotlivé segmenty podle:

- customer count,
- transaction volume,
- transaction frequency,
- average transaction value,
- trendu aktivity.

---

## 10. Business interpretation

Výstupem nemají být pouze SQL tabulky.

Každá významnější analýza by měla být zakončena krátkou interpretací:

**Finding → Evidence → Business implication**

Například:

> High-value customers represent only a small share of the customer base but generate a disproportionately large share of transaction volume.

A následně:

> This segment may therefore deserve priority retention and cross-selling attention.

Doporučení musí být formulována jako analytická hypotéza, nikoliv jako tvrzení o skutečné strategii banky.

---

## 11. Vizualizace

Projekt bude obsahovat jednoduchý Python notebook pro EDA a vizualizaci.

Doporučené grafy:

1. Customer segments distribution
2. Transaction volume over time
3. Active vs. dormant customers over time
4. Customer value distribution
5. Transaction volume by region
6. Regional performance normalized by population
7. Activity trend of selected customer segments

Python zde nebude hlavním nástrojem projektu. Jeho úlohou je především:

- ověřit data,
- provést EDA,
- vytvořit několik přehledných vizualizací.

---

## 12. Doporučená struktura GitHub repository

```text
bank-customer-segmentation/
│
├── data/
│   ├── customers.csv
│   ├── accounts.csv
│   ├── transactions.csv
│   └── regions.csv
│
├── sql/
│   ├── 01_data_quality.sql
│   ├── 02_customer_value.sql
│   ├── 03_customer_segments.sql
│   ├── 04_dormant_accounts.sql
│   ├── 05_activity_trends.sql
│   ├── 06_declining_customers.sql
│   ├── 07_region_performance.sql
│   └── 08_segment_comparison.sql
│
├── notebooks/
│   └── eda.ipynb
│
├── scripts/
│   └── generate_data.py
│
├── README.md
└── requirements.txt
```

---

## 13. Data quality checks

Před analytickou částí projektu budou provedeny základní kontroly:

- unikátnost primárních klíčů,
- existence všech foreign keys,
- chybějící hodnoty,
- záporné / nulové částky,
- transakce před otevřením účtu,
- transakce po uzavření účtu,
- účty bez zákazníka,
- zákazníci bez účtu,
- extrémní hodnoty.

To umožní ukázat, že analytik nejdříve ověřuje kvalitu dat a teprve potom interpretuje výsledky.

---

## 14. Očekávané výstupy

Projekt by měl na konci nabídnout:

### Customer intelligence

- segmentaci zákazníků,
- customer value,
- activity score,
- dormant customers,
- declining customers.

### Transaction analysis

- transaction volume,
- transaction frequency,
- average transaction value,
- transaction type patterns,
- časové trendy.

### Regional analysis

- regionální ranking,
- normalized regional performance,
- customer activity per region.

### Business recommendations

Krátká sada doporučení pro hypotetické:

- marketing team,
- retention team,
- product team,
- customer relationship management.

---

## 15. Co projekt demonstruje z pohledu recruitera

Projekt má ukázat především schopnost:

1. Převést business problém do analytických otázek.
2. Pracovat s relačními daty.
3. Psát čitelné a strukturované SQL.
4. Používat CTE a window functions.
5. Pracovat s časovými daty.
6. Vytvářet vlastní analytické metriky.
7. Segmentovat zákazníky podle smysluplných kritérií.
8. Validovat kvalitu dat.
9. Interpretovat výsledky.
10. Převést výsledky do business doporučení.

---

## 16. Rozsah a obtížnost

Projekt je zamýšlen jako **mírně pokročilý začátečnický / juniorní SQL portfolio projekt**.

Neměl by se zbytečně rozšiřovat o:

- machine learning,
- komplexní churn prediction,
- fraud detection,
- rozsáhlý Power BI dashboard,
- pokročilé statistické modelování.

Cílem není ukázat všechny technologie najednou.

Cílem je vytvořit kvalitní a realistickou analytickou případovou studii, ve které je hlavním nástrojem SQL a hlavním tématem customer intelligence ve finančním sektoru.

---

## 17. Poznámka k syntetickým datům

Pokud budou použita vlastní syntetická data, README musí explicitně uvést:

> The dataset used in this project is synthetic and does not represent real customers, accounts or transactions of any financial institution.

Parametry generování dat by měly být navrženy tak, aby vytvářely realistické, ale záměrně anonymní vzorce chování.

Je vhodné zahrnout například:

- různé customer value levels,
- rozdílnou aktivitu,
- dormant customers,
- sezónnost,
- regionální rozdíly,
- různé typy účtů,
- různé transaction types.

---

## 18. Finální projektový příběh

Celý projekt by měl být prezentován jako následující analytický příběh:

```text
RAW BANKING DATA
       ↓
DATA QUALITY
       ↓
RELATIONAL DATA MODEL
       ↓
CUSTOMER & TRANSACTION METRICS
       ↓
CUSTOMER SEGMENTATION
       ↓
ACTIVITY & DORMANCY ANALYSIS
       ↓
TIME TRENDS
       ↓
REGIONAL ANALYSIS
       ↓
BUSINESS INSIGHTS
       ↓
RECOMMENDATIONS
```

Tím vznikne projekt, který není pouze demonstrací SQL syntaxe, ale kompletní ukázkou základního analytického workflow.