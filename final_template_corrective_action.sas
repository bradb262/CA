

/*The following code will delete all data sets in a particular library.*/
/*Having data sets from previous samples in a library may comprise the integrity of the current sample*/
proc delete data=work._all_;
run;


/*Identify the file path here:*/
/*Path is dynamically identified based on the location of the code*/
%let pull_folder = %qsubstr(%sysget(SAS_EXECFILEPATH),
						1,
						%length(%sysget(SAS_EXECFILEPATH))-%length(%sysget(SAS_EXECFILEname))
						);

/*File directory is identified here*/
filename indata pipe "dir &pull_folder. /b " lrecl=32767; /*lrecl=addresses maximum record length problem*/


/*Locate and read in the provider data.*/
/* This section searches the directory you specified to find all the file names with an extension of .xlsx.*/
/* The names of files found will be stored in file_list*/

data file_list;
length fname $90 in_name out_name $32;
infile indata truncover;
input fname $ 90.;
in_name=translate(scan(fname,1,'.'),'_','-');
out_name=cats('_',in_name); 
if upcase(scan(fname,-1,'.'))='XLSX';                                                                                                          
run;





/*You will loop through the names in the file_list2 to read the data in.*/
/*The current code will name the file "RawProviderData" but it can be generalized to read and name multiple files dynamically in the future*/

data _null_;
  set file_list end=last;
  call symputx(cats('dsn',_n_),in_name);
  call symputx(cats('outdsn',_n_),out_name);
  if last then call symputx('n',_n_);
run;

%macro readdata(outtablename,sheetname);

   %do i=1 %to &n;

PROC IMPORT OUT= work.&outtablename
			DATAFILE= "&pull_folder.\&&dsn&i...xlsx"
            DBMS=EXCEL REPLACE;
			GETNAMES=YES;
			SHEET="&sheetname";
RUN;

%end;
%mend;

/*Read in the raw data from the first sheet of the report-this will become our raw data*/
%readdata(rawdata,rawdata);
%readdata(drg_desc,drg_desc);
%readdata(proc_codes, proc_codes);
%readdata(dx_desc, dx_desc);
%readdata(header,header);


/*Read IN the discharge status code from the INSIGHT Reference Template Access DB*/
PROC IMPORT OUT= WORK.dischargecode
            DATATABLE= "Status Code Description Table"
            DBMS=ACCESS REPLACE;
     DATABASE="W:\InSight Templates\Look up tables.mdb";
     SCANMEMO=YES;
     USEDATE=NO;
     SCANTIME=YES;
RUN;




/******************************************************************************************************/
/****Section 1: Data preparation for summary table generation *****************************************/
/******************************************************************************************************/



/*Change the format of CHI_DRG_DIAGNOSIS_RELATED_GROUP_ to text so it can be used to merge on */
/*When merging, components being merged on must be same data type, set to character as there will be no calculations on this field*/
DATA RAWDATA2;
SET RAWDATA;
/*CHAR_DRG= PUT(CHI_DRG_DIAGNOSIS_RELATED_GROUP_,3.);*/
char_discharge_code= PUT(CHI_PATIENT_DISCHARGE_STATUS_CD, 3.);
RUN;



/*Macro variable creation steps-create a macro varaible to store all unique DRGs*/
proc sql noprint;
	select DISTINCT(CHI_DRG_DIAGNOSIS_RELATED_GROUP_)
	into :varlist separated by ' ' /*STORE each DRG code in the list is sep. by a single space*/
from RAWDATA2;
quit;


%let cntlist = &sqlobs; /*Store a count of the number of oscar codes*/
%put &varlist; /*Print the codes to the log to be sure our list is accurate*/



/*Merge the DRG descriptions from the ms drg decode table to our current data set*/
proc sql;
create table rawdata3 as
	select t1.*, t2.diagnosis_related_group_title_de AS MS_DRG_TITLE
	from rawdata2 as t1  LEFT join drg_desc as t2 on 
		t1.chi_drg_diagnosis_related_group_ = t2.diagnosis_related_group_code;
quit;

/*Merge the dicharge code descriptions to our current data set*/
proc sql;
create table rawdata4 as
	select t1.*, t2.Description as Discharge_Description
	from rawdata3 as t1  LEFT join dischargecode as t2 on 
t1.CHI_Patient_discharge_status_cd = t2.status_code;
quit;




/*Merge the provider type data to the raw data so this can be used in summary output tables*/
data rawdata5;
length facility $ 18;
set rawdata4;
IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=0001 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=0879 THEN Facility='STCH';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=0880 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=0899 THEN Facility='ORD DEMO';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=0900 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=0999 THEN Facility='Retired ';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=1000 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=1199 THEN Facility='Federal Qualified Health';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=1200 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=1224 THEN Facility='Retired-Alcohol/Drug Hospital';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=1225 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=1299 THEN Facility='Medical Access';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=1300 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=1399 THEN Facility='CAH';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=1400 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=1499 THEN Facility='CMHC';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=1500 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=1799 THEN Facility='Hospice';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=1800 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=1989 THEN Facility='Federal Qualified Health';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=1900 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=1999 THEN Facility='Religious Non-Medical Health';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=2000 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=2299 THEN Facility='LTCH';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=2300 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=2999 THEN Facility= 'Renial Dialysis';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=3000 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=3024 THEN Facility='Retired';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=3025 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=3099 THEN Facility='IRF';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=3100 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=3199 THEN Facility='Home Health';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=3200 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=3299 THEN Facility='CORF';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=3300 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=3999 THEN Facility='Home Health';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=4000 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=4499 THEN Facility='Psych Unit';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=4500 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=4599 THEN Facility='CORF';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=4600 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=4799 THEN Facility='CMHC';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=4800 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=4899 THEN Facility='CORF';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=4900 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=4999 THEN Facility='CMHC';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=5000 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=6499 THEN Facility='SNF';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=6500 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=6989 THEN Facility='ORF';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=7000 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=8499 THEN Facility='Home Health';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=8500 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=8999 THEN Facility='Rural Health';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=9000 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=9799 THEN Facility='Home Health';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=9800 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=9899 THEN Facility='Transplant Centers';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,4)>=3100 AND substr(BP_Billing_PROV_NUM_OSCAR,3,4) <=3199 THEN Facility='Home Health';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,1)= 'S' THEN FACILITY= 'Psych Unit';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,1)= 'T' THEN FACILITY= 'Rehab Unit';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,1)= 'U' THEN FACILITY= 'Swing Bed-STCH';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,1)= 'Z' THEN FACILITY= 'Swing Bed-CAH';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,1)= 'M' THEN FACILITY= 'Psych Unit in CAH';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,1)= 'R' THEN FACILITY= 'Rehab Unit in CAH';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,1)= 'W' THEN FACILITY= 'Swing Bed for LTCH';
ELSE IF substr(BP_Billing_PROV_NUM_OSCAR,3,1)= 'Y' THEN FACILITY= 'Swing Bed for IRF';
ELSE Facility='OTHER ';
run;



/*Create a new column to identify contract*/
Data pre_filter_data;
	Set rawdata5;
	/*Claims_Sampled_&Contract-all the claims in the data set*/
	If CH_CONTRACTOR_NUM='05901' or  CH_CONTRACTOR_NUM='05001'
			then contract='J5';
			else contract='J8';
Run;



/*Create a macro to loop over J5 and J8 contracts for each drg*/
%macro runtab(x,contract);

/*Filter the data to contain records for only the specified contract*/
proc sql;
CREATE TABLE data_&contract AS 
	SELECT  *
	FROM pre_filter_data
	WHERE CONTRACT="&contract";
	QUIT;


/*Create flag if CHF Amount Paid = 0.00*/
/*will use the assumption these claims are denied */
/*1 will indicate it has been denied, 0 will indicate all other outcomes*/
data data2_&contract; 
set data_&contract; 
denied_count=ifc(ch_idr_nat_l_paid_status_cd="D",'1','0');
paid_count=ifc(ch_idr_nat_l_paid_status_cd="P",'1','0');
rejected_count=ifc(ch_idr_nat_l_paid_status_cd="R",'1','0');
run; 


/*CREATE A SUMMARY TABLE COUNTING BENES AND CLAIMS PER DRG FOR contract*/
proc sql;
CREATE TABLE SUMMARIES_&contract AS 
	SELECT  DISTINCT(CHI_DRG_DIAGNOSIS_RELATED_GROUP_) as DISTINCT_DRG,
			LOWCASE(MS_DRG_TITLE) AS DRG_DESCRIPTION,
			CONTRACT,
			COUNT(DISTINCT BENE_CLAIM_HIC_NUM) as BENE_COUNT,
			COUNT(DISTINCT CH_ICN) as CLAIM_COUNT,
			COUNT(DISTINCT BP_Billing_Prov_Num_OSCAR)as Num_Providers,
			SUM(CHF_AMT_PAID) as SUM_AMOUNT format=dollar20.2
	FROM data2_&contract
	GROUP BY Contract,CHI_DRG_DIAGNOSIS_RELATED_GROUP_;
	QUIT;



/**************************************************************************/
/*SECTION 2                                                               */
/*this section shows how much each discharge code per claim counts per DRG*/
/**************************************************************************/



/*Total claim count calculation*/
proc sql;
CREATE TABLE pre_discharge1_&x AS
	SELECT CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
		   CHI_PATIENT_DISCHARGE_STATUS_CD as DISCHARGE_CODE,
			discharge_description,
			CH_ICN,
			count (DISTINCT CH_ICN) as claim_count
		FROM data2_&contract
where CHI_DRG_DIAGNOSIS_RELATED_GROUP_ eq &x;
	run;



	/*Filter col*/
	proc sql;
CREATE TABLE discharge1_&x AS
	SELECT CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
		   DISCHARGE_CODE,
			discharge_description,	
			COUNT(DISTINCT CH_ICN) as unique_claims,
			claim_count
	FROM pre_discharge1_&x
	where CHI_DRG_DIAGNOSIS_RELATED_GROUP_ eq &x
Group by DISCHARGE_CODE;
	run;


/*Calculate percents*/
proc sql;
CREATE TABLE discharge2_&x AS
	SELECT CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
		    DISCHARGE_CODE,
			discharge_description,	
			 unique_claims,
			(unique_claims/claim_count) as pct format=percent8.2
	FROM discharge1_&x
	where CHI_DRG_DIAGNOSIS_RELATED_GROUP_ eq &x
order by DISCHARGE_CODE;
	run;


/*Drops all duplicate records*/
	 proc sort data = discharge2_&x out = discharge3_&x nodupkey;
	 by _all_;
	 by DESCENDING pct;
run;




/**************************************************************************/
/*SECTION 3                                                               */
/*this section summarizes primary procedure codes per DRG                 */
/**************************************************************************/


proc sql;
	CREATE TABLE PROC_SUMMARY_&x AS
		SELECT 
		DISTINCT (CHI_Procedure_Cd_01) AS PRIMARY_PROC_CODE,
		CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
        COUNT(DISTINCT CH_ICN) as CLAIM_COUNT,
		COUNT(DISTINCT BENE_CLAIM_HIC_NUM) as BENE_COUNT,
		SUM(CHF_AMT_PAID) as AMOUNT_PAID format=dollar20.2
	FROM data2_&contract
	WHERE CHI_DRG_DIAGNOSIS_RELATED_GROUP_ eq &x
	GROUP BY PRIMARY_PROC_CODE 
	HAVING PRIMARY_PROC_CODE NE '~'
ORDER BY AMOUNT_PAID DESC;
	QUIT;


/*Merge the description field in*/
/*use left outer join so we do not eliminate anything from raw data that does not have a match in the descriptor table*/
proc sql;
create table proc_summary2_&x as
	select t1.*, t2.procedure_subclassification_code as Proc_code_desc
	from PROC_SUMMARY_&x as t1 LEFT JOIN proc_codes as t2 on 
	t1.PRIMARY_PROC_CODE = t2.procedure_code;
quit;

/*Sort data by amount paid*/
proc sort data=proc_summary2_&x out=proc_summary3_&x;
by _ALL_;
by DESCENDING amount_paid;
run;



/**************************************************************************/
/*SECTION 4                                                               */
/*this section summarizes other procedure codes per DRG                 */
/**************************************************************************/				

data want;
set data2_&contract;
array labs CHI_Procedure_Cd_01-CHI_Procedure_Cd_06;

do _t = 1 to dim(labs);
  lab = labs[_t];
  
  output;
end;
keep ch_icn BENE_CLAIM_HIC_NUM lab CHI_DRG_DIAGNOSIS_RELATED_GROUP_ CHF_AMT_PAID;
run;

proc sort data = want out = want nodupkey;
by ch_icn BENE_CLAIM_HIC_NUM lab CHI_DRG_DIAGNOSIS_RELATED_GROUP_ CHF_AMT_PAID; 	 
run;

proc sql;
CREATE TABLE OTHER_PROCD_&x AS
	SELECT CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
	LAB AS OTHER_PROC_CODE,
	COUNT(DISTINCT CH_ICN) AS CLAIM_COUNT,
	COUNT(DISTINCT BENE_CLAIM_HIC_NUM) AS Bene_count
FROM WANT
WHERE CHI_DRG_DIAGNOSIS_RELATED_GROUP_ EQ &x
GROUP BY OTHER_PROC_CODE
HAVING OTHER_PROC_CODE NE '~';
QUIT;

/*Merge the description field in*/
/*use left outer join so we do not eliminate anything from raw data that does not have a match in the descriptor table*/
proc sql;
create table other_proc_summary_&x as
	select t1.*, t2.procedure_subclassification_code AS Description
	from OTHER_PROCD_&x as t1 LEFT JOIN proc_codes as t2 on 
	t1.OTHER_PROC_CODE = t2.procedure_code;
quit;

/*Remove all duplicate records, and sort by claim count*/
proc sort data = other_proc_summary_&x out = other_proc_summary_&x NODUPKEY;
by _all_;
by DESCENDING CLAIM_COUNT;
run;




			

/**************************************************************************/
/*SECTION 5 Primary Diagnosis Code Summary                                */
/*this section summarizes the primary diagnosis code per DRG              */
/**************************************************************************/	
proc sql;
CREATE TABLE prime_dx_summary_&x AS
	SELECT CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
			CH_Diag_Cd_Principal as Primary_DX_Code,
			Count(DISTINCT CH_ICN) AS Claim_COUNT,
			COUNT(DISTINCT BENE_CLAIM_HIC_NUM) AS Bene_count,
			SUM (CHF_AMT_PAID) AS amount_paid format=dollar20.2
from data2_&contract
where CHI_DRG_DIAGNOSIS_RELATED_GROUP_ eq &x
GROUP BY Primary_DX_Code
HAVING Primary_DX_Code NE '~';
quit;


/*Merge the description field in*/
/*use left outer join so we do not eliminate anything from raw data that does not have a match in the descriptor table*/
proc sql;
create table prime_dx_summary2_&x as
	select t1.*, t2.diagnosis_code_description AS Description
	from prime_dx_summary_&x as t1 LEFT JOIN dx_desc as t2 on 
	t1.Primary_DX_Code = t2.diagnosis_code;
quit;


proc sort data=prime_dx_summary2_&x out=prime_dx_summary3_&x nodupkey;
by _all_;
by DESCENDING amount_paid;
run;








/**************************************************************************/
/*SECTION 6 OTHER Diagnosis Code Summary                                */
/*this section summarizes the other diagnosis code per DRG              */
/**************************************************************************/	
data OTHER_DX_LONG;
set data2_&contract;
array labs CH_DIAG_CD_01-CH_DIAG_CD_10;

do _t = 1 to dim(labs);
  lab = labs[_t];
  
  output;
end;
keep ch_icn BENE_CLAIM_HIC_NUM lab CHI_DRG_DIAGNOSIS_RELATED_GROUP_ ;
run;


proc sort data = OTHER_DX_LONG out = OTHER_DX_LONG nodupkey;
by ch_icn lab CHI_DRG_DIAGNOSIS_RELATED_GROUP_ ; 	 
run;

proc sql;
CREATE TABLE OTHER_DX_LONG_&x AS
	SELECT CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
	LAB AS OTHER_DX_CODE,
	COUNT(DISTINCT CH_ICN) AS CLAIM_COUNT,
	COUNT(DISTINCT BENE_CLAIM_HIC_NUM) AS Bene_count
FROM OTHER_DX_LONG
WHERE CHI_DRG_DIAGNOSIS_RELATED_GROUP_ EQ &x
GROUP BY OTHER_DX_CODE
HAVING OTHER_DX_CODE NE '~';
QUIT;


/*Merge the description field in*/
/*use left outer join so we do not eliminate anything from raw data that does not have a match in the descriptor table*/
proc sql;
create table OTHER_DX_LONG2_&x as
	select t1.*, t2.diagnosis_code_description AS Description
	from OTHER_DX_LONG_&x as t1 LEFT JOIN dx_desc as t2 on 
	t1.OTHER_DX_CODE = t2.diagnosis_code;
quit;


proc sort data = OTHER_DX_LONG2_&x out = OTHER_DX_LONG2_&x NODUPKEY;
by _all_;
by DESCENDING CLAIM_COUNT;
run;

proc sql;
drop table OTHER_DX_LONG_&x;
quit;






/**************************************************************************/
/*SECTION 7  Provider Summary                                             */
/*this section summarizes the providers associated with DRG                */
/**************************************************************************/
PROC SQL;
	CREATE TABLE PROVIDERS_&x as
		SELECT
		CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
		BP_BILLING_PROV_NUM_NPI,
		BP_BILLING_PROV_NUM_OSCAR,
		contract,
		FPX_FACILITY_PROV_NPICS_NAME_LEG,
		Facility,
		FPX_Facility_PROV_NPICS_PRACTIC1 AS CITY,
        FPX_Facility_PROV_NPICS_PRACTIC2 AS STATE,
		FPX_Facility_PROV_NPICS_PRACTIC3 AS ZIP,
		COUNT(DISTINCT CH_ICN) AS CLAIM_COUNT,
		COUNT(DISTINCT BENE_CLAIM_HIC_NUM) AS BENEFICIARIES,
		sum (denied_count= '1') AS Denied_claims,
		sum (paid_count='1') AS paid_claims,
		sum (rejected_count='1') AS rejected_claims,
		SUM (CHF_AMT_PAID) as AMOUNT_PAID format=dollar20.2
	FROM data2_&contract
	where CHI_DRG_DIAGNOSIS_RELATED_GROUP_= &x
	GROUP BY BP_BILLING_PROV_NUM_OSCAR;
	quit;

proc sort data=PROVIDERS_&x nodupkey;
by _all_;
by DESCENDING amount_paid;
run;





/**************************************************************************/
/*SECTION 8 Length of Stay Analysis                                        */
/*this section summarizes the Length of stay per  each DRG                */
/**************************************************************************/

proc sql;
	CREATE TABLE LOS_&x AS
		SELECT 	CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
		(CHD_CLAIM_THROUGH_DATE-CHD_CLAIM_FROM_DATE +1) as LOS,
		COUNT(DISTINCT CH_ICN) AS CLAIM_COUNT,
		COUNT (DISTINCT BENE_CLAIM_HIC_NUM) AS Bene_Count,
		Facility
	FROM data2_&contract
	where CHI_DRG_DIAGNOSIS_RELATED_GROUP_= &x
	group by CHI_DRG_DIAGNOSIS_RELATED_GROUP_, LOS;
	quit;

/*Remove all duplicate records created above*/
proc sort data=LOS_&x nodupkey;
by _all_;
by los;
run;



/**************************************************************************/
/*SECTION 9 Summary by Facility type and Provider Count                   */
/*this section summarizes the Length of stay per  each DRG                */
/**************************************************************************/
proc sql;
	create table facility_type AS
		SELECT FACILITY,
			COUNT (FACILITY) as Facility_Count,
			COUNT (DISTINCT BP_BILLING_PROV_NUM_OSCAR) AS PROVIDER_COUNT,
			COUNT (DISTINCT CH_ICN) AS CLAIM_COUNT,
			COUNT (DISTINCT BENE_CLAIM_HIC_NUM) AS Bene_Count,
			SUM (CHF_AMT_PAID) as AMOUNT_PAID format=dollar20.2
		FROM data2_&contract
/*		WHERE CHI_DRG_DIAGNOSIS_RELATED_GROUP_= &x*/
		GROUP BY FACILITY
		ORDER BY AMOUNT_PAID DESC;
QUIT;



/**************************************************************************/
/*SECTION 9 create a type of bill summary chart                           */
/*this sections summarizes the type of bill per  each DRG                */
/**************************************************************************/
proc sql;
	create table tob_summary_&x AS
		SELECT 
			   DISTINCT (CHI_TOB_TYPE_OF_BILL_CD) as TOB,
		       CHI_TOB_TYPE_OF_BILL_CD_DESC,
			   CHI_DRG_DIAGNOSIS_RELATED_GROUP_,
			   COUNT(DISTINCT CH_ICN) AS CLAIM_COUNT,
		       COUNT(DISTINCT BENE_CLAIM_HIC_NUM) AS BENEFICIARIES,
               SUM (CHF_AMT_PAID) as AMOUNT_PAID format=dollar20.2
		FROM data2_&contract
        WHERE CHI_DRG_DIAGNOSIS_RELATED_GROUP_= &x
		GROUP BY TOB
        ORDER BY AMOUNT_PAID DESC;
QUIT;



/**************************************************************************/
/*SECTION 10                   Document Generation                        */
/**************************************************************************/



/****************************************/
/************ SHEET 1:Main Summary Page**/
/****************************************/


/*Define the location for the export of the data. Will print results to the same file the code is in*/
ods tagsets.excelxp file="&pull_folder.drg_&x._&contract..xml" 
style=SeasidePrinter /*Use the style template defined above*/
	options(sheet_interval="none" /*We want multiple tables on a single sheet, so define sheet interval as none*/
			embedded_titles = 'yes' /*Titles will appear in the worksheet, not as headers, which is the default.*/
			sheet_name="Analyst Summary" /*First sheet general summary data*/
			skip_space='3,0,1,1,1' /*Spacing between tables*/
			orientation='portrait' /*When printing, default to landscape orientation*/
			FitToPage = 'yes' 
			Pages_FitWidth = '1' /*Fit to 1 page across.*/
			Pages_FitHeight = '300' /*allow a sheet to be multiple pages long*/
			autofit_height='Yes' /*Excel determines row height*/
);


proc print data=work.header noobs;
var criteria / style(data)={width= 34 just=c} style(header)={width=34 just=c};
var information / style(data)={just=L} style(header)={just=c};
title1 "Analysis: CMS Corrective Action Q4";
title2 "DRG Analyzed: &x";
/*title3 "Analysis Run Between &lowdate and &highdate";*/
run;




/*Print summary of ALL DRG utilazation to main Analyst Response Page*/
proc print data=work.SUMMARIES_&contract width=min noobs label;
var distinct_drg / style(data)={just=l} style(header)={just=c};
var drg_description / style(data)={just=l};
var contract/style(header)={just=c} style(data)={just=c};
var bene_count / style(data)={just=c} style(header)={just=c};
var claim_count / style(data)={just=c } style(header)={just=c};
var num_providers / style(data)={just=c } style(header)={just=c};
var sum_amount / style(data)={width= 8 just=c} style(header)={width=8 just=c};


label distinct_drg = 'DRG Group'
	  bene_count= '# Benes'
      Claim_count= '# Claims' 
	  Num_providers= '# Providers'
      sum_amount='Amt_Paid';
title1 "DRG Utilization Summary Report";

run;







/*PRINT THE TOP 20 PROVIDERS BILLING DRG X BASED ON AMOUNT PAID*/
proc print data=providers_&x(obs=20) width=min noobs label style(header)={just=l foreground=black};

        var CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /style(header)=[font_weight=BOLD];
		var BP_BILLING_PROV_NUM_NPI /style(header)=[font_weight=BOLD];
		var BP_BILLING_PROV_NUM_OSCAR /style(header)=[font_weight=BOLD];
		var contract /style(header)=[font_weight=BOLD];
		var FPX_FACILITY_PROV_NPICS_NAME_LEG /style(header)=[font_weight=BOLD];
		var Facility /style(header)=[font_weight=BOLD];
		var CITY / style(data)=[width= 25 just=c] style(header)=[width=25 just=c font_weight=BOLD];
        var STATE / style(data)=[width= 175 just=c] style(header)=[width=175 just=c font_weight=BOLD];
		var ZIP / style(data)=[width= 175 just=c] style(header)=[width=175 just=c font_weight=BOLD];
		var CLAIM_COUNT / style(data)=[width= 175 just=c] style(header)=[width=175 just=c font_weight=BOLD];
		var BENEFICIARIES / style(data)=[width= 175 just=c] style(header)=[width=175 just=c font_weight=BOLD];
		var denied_claims / style(data)=[cellwidth=4in just=c] style(header)=[cellwidth=4in just=c font_weight=BOLD];
		var paid_claims / style(data)=[cellwidth=4in just=c] style(header)=[cellwidth=4in just=c font_weight=BOLD];
		var rejected_claims / style(data)=[cellwidth=4in just=c] style(header)=[cellwidth=4in just=c font_weight=BOLD];
		var AMOUNT_PAID / style(data)=[width= 175 just=c] style(header)=[width=175 just=c font_weight=BOLD];

label CHI_DRG_DIAGNOSIS_RELATED_GROUP_ = 'DRG GROUP'
	  BP_BILLING_PROV_NUM_NPI = 'NPI Number'
      BP_BILLING_PROV_NUM_OSCAR = 'OSCAR Number'
	  FPX_FACILITY_PROV_NPICS_NAME_LEG = 'Facility Name'
	  City = 'City'
      State= 'State'
	  Zip = 'Zip'
      Claim_count= '# Claims' 
	  Beneficiaries= '# Benes'
      denied_claims= 'Claims Denied'
	  paid_claims="Claims Paid"
	  rejected_claims="Claims Rejected"
	  Amount_Paid='Amount Paid';
title1 "Top 20 Provider Billing DRG &x Based on Amount Paid ";
run;


/*PRING THE TOP 15 PRIMARY DIAGNOSIS CODES BILLED WITH DRG X*/
proc print data=PRIME_DX_SUMMARY3_&x (obs=15) width=min noobs label;
var CHI_DRG_DIAGNOSIS_RELATED_GROUP_/style(header)=[cellwidth=0.5in just=l];
var Primary_DX_Code Description / style(data)={tagattr="format:@"};
var Claim_COUNT Bene_Count amount_paid;
label CHI_DRG_DIAGNOSIS_RELATED_GROUP_ = 'DRG GROUP'
	  Primary_DX_Code = 'Primary DX Code'
	  Description = 'Diagnosis Code Desc.'
      Claim_count= '# Claims'
	  Bene_Count='# Benes'
      Amount_paid= 'Amt_Paid';
title1 justify=left "Top 15 Primary Diagnosis Codes Billed with DRG &X ";
run;


/*Print a Summary table for ALL DRGs per facility type to main Analyst Repost Page*/
proc report data=work.facility_type;
column Facility Facility_count provider_count claim_count bene_count amount_paid;
title j=l "Facility Type Summary Report for DRG &x";

/*The total column should have a heavy left border and content should be centered*/
define Facility /display style(column) = {just=center  width=1.5in} ;
define Facility /display style(column) = {just=left width=1.5in} ;

/*The measure column should have a heavy right border and content should be centered*/
define Facility_count /display style(Header) = {just=center} ;
define Facility_count /display style(column) = {just=left width=1.5in} ;

/*Heavy underline under all header. Center content of each column*/
define provider_count /display style(Header) = {just=center} '# Providers';
define provider_count /display style(column) = {just=left width=1.5in} ;

define claim_count /display style(Header) = {just=center} '# Claims';
define claim_count /display style(column) = {just=right width=1.5in} ;

define bene_count /display style(Header) = {just=center} '# Benes';
define bene_count /display style(column) = {just=right width=1.5in} ;

define amount_paid /display style(Header) = {just=center} 'Amt_Paid';
define amount_paid /display style(column) = {just=right width=1.5in} ;

run;


/*PRING THE TOP 15 PROCEDURE CODES BEING BILLED WITH DRG X*/
PROC PRINT DATA=proc_summary3_&x (obs=15) width=min noobs label;
var CHI_DRG_DIAGNOSIS_RELATED_GROUP_/style(data)={tagattr="format:@"};
var PRIMARY_PROC_CODE Proc_code_desc claim_count BENE_COUNT amount_paid ;
label CHI_DRG_DIAGNOSIS_RELATED_GROUP_ = 'DRG GROUP'
	  PRIMARY_PROC_CODE = 'Primary Procedure Code'
      Proc_code_desc = 'Procedure Code Desc.'
	  Claim_Count= '# Claims'
	  Bene_Count= '# Benes'
      Amount_Paid='Amt_Paid';
title1 justify=left "Top 15 Primary Procedure Codes Billed with DRG &X ";

run;


/****************************************/
/************ SHEET 2: Discharge Code ***/
/****************************************/
ods tagsets.excelxp options(sheet_interval="table"); /*Changing the sheet interval triggers the new sheet to start*/
ods tagsets.excelxp options(sheet_interval="none" /*Change the interval back to none to keep all part b tables on the same sheet*/
embedded_titles = 'yes' /*Titles will appear in the worksheet, not as headers, which is the default.*/
			sheet_name="Discharge Code Summary Report" /*First sheet will contain part A data*/
			skip_space='3,0,1,1,1' /*Spacing between tables*/
			/*orientation='landscape' /*When printing, default to langscape orientation*/
			FitToPage = 'yes' 
			Pages_FitWidth = '1' /*Fit to 1 page across.*/
			Pages_FitHeight = '100' /*allow a sheet to be multiple pages long*/
			autofit_height='Yes' /*Excel determines row height*/
);


/*Discharge code related to DRG X report*/
proc report data=work.discharge3_&x;/*define the table to export*/
column CHI_DRG_DIAGNOSIS_RELATED_GROUP_ Discharge_CODE Discharge_Description unique_claims pct;
title1 height=17pt bold underline=1 'Discharge Code Summary'; /*Insert sheet title here*/
title2 ' '; /*Space between sheet title and table title*/
title3 'Summary Per Discharge Code'; /*Table title*/
define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=center borderleftwidth=5 width=1in } ;
define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=left width=1in} ;

define DISCHARGE_CODE /display style(column) = {just=center borderleftwidth=1 width=1in } ;
define DISCHARGE_CODE /display style(column) = {just=left width=1in} ;

define discharge_description /display style(column) = {just=center borderleftwidth=1 width=5in } ;
define discharge_description /display style(column) = {just=left width=5in} ;

define unique_claims /display style(column) = {just=center borderleftwidth=1 width=1in } 'Claims' ;
define unique_claims /display style(column) = {just=left width=1in} ;

define pct /display style(column) = {just=center borderleftwidth=5 width=1in } ;
define pct /display style(column) = {just=left width=1in} ;
run;





/****************************************/
/************ SHEET 3:Procedure Codes ***/
/****************************************/

ods tagsets.excelxp options(sheet_interval="table"); /*Changing the sheet interval triggers the new sheet to start*/
ods tagsets.excelxp options(sheet_interval="none" /*Change the interval back to none to keep all part b tables on the same sheet*/
embedded_titles = 'yes' /*Titles will appear in the worksheet, not as headers, which is the default.*/
			sheet_name="Procedure Code Summary" /*First sheet will contain part A data*/
			skip_space='3,0,1,1,1' /*Spacing between tables*/
			/*orientation='landscape' /*When printing, default to langscape orientation*/
			FitToPage = 'yes' 
			Pages_FitWidth = '1' /*Fit to 1 page across.*/
			Pages_FitHeight = '100' /*allow a sheet to be multiple pages long*/
			autofit_height='Yes' /*Excel determines row height*/
);


/*Procedure codes billed with DRG summary table printed */

proc report data=work.proc_summary3_&x;/*define the table to export*/
column CHI_DRG_DIAGNOSIS_RELATED_GROUP_ PRIMARY_PROC_CODE Proc_code_desc Claim_COUNT BENE_COUNT AMOUNT_PAID;
title1 height=17pt bold underline=1 'Procedure Code Summary Report'; /*Insert sheet title here*/
title2 height=12pt '(totals for first listed Surgical Procedure Code Only)';
/*The total column should have a heavy left border and content should be centered*/
define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=center borderleftwidth=5 width=1.8in } ;
define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=left width=2in} ;

define PRIMARY_PROC_CODE / display
	style(column)={tagattr='Format:@'}; /*Retain formatting */

define CLAIM_COUNT /display style(column) = {just=center width=2in } ;
define CLAIM_COUNT /display style(column) = {just=left width=2in} ;

define BENE_COUNT /display style(column) = {just=center width=2in };
define BENE_COUNT /display style(column) = {just=left width=2in} ;

define Amount_Paid /display style(column) = {just=center  width=2in } ;
define Amount_Paid /display style(column) = {just=left width=2in} ;
run;





/****************************************/
/***** SHEET 3:Other Procedure Codes ****/
/****************************************/

ods tagsets.excelxp options(sheet_interval="table"); /*Changing the sheet interval triggers the new sheet to start*/
ods tagsets.excelxp options(sheet_interval="none" /*Change the interval back to none to keep all part b tables on the same sheet*/
embedded_titles = 'yes' /*Titles will appear in the worksheet, not as headers, which is the default.*/
			sheet_name="Other Procedure Codes" /*First sheet will contain part A data*/
			skip_space='3,0,1,1,1' /*Spacing between tables*/
		/*	orientation='landscape' /*When printing, default to langscape orientation*/
			FitToPage = 'yes' 
			Pages_FitWidth = '1' /*Fit to 1 page across.*/
			Pages_FitHeight = '100' /*allow a sheet to be multiple pages long*/

			autofit_height='Yes' /*Excel determines row height*/
);



proc report data=work.other_proc_summary_&x; /*define the table to export*/
column CHI_DRG_DIAGNOSIS_RELATED_GROUP_ OTHER_PROC_CODE Description CLAIM_COUNT bene_count;
title1 height=17pt bold underline=1 'Other Procedure Code Report'; /*Insert sheet title here*/
title2 height=12pt '(Cumulative totals over all procedure code fields)';
define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=center borderleftwidth=5 width=1.8in } ;
define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=left width=2in} ;


define OTHER_PROC_CODE / display
	style(column)={tagattr='Format:@'}; /*Retain formatting */


define claim_count /display style(column) = {just=center borderleftwidth=5 width=1.8in } ;
define claim_count /display style(column) = {just=left width=2in} ;



define bene_count /display style(column) = {just=center borderleftwidth=5 width=1.8in } ;
define bene_count /display style(column) = {just=left width=2in} ;

run;

/****************************************/
/************ SHEET 4:Primary DX ********/
/****************************************/

ods tagsets.excelxp options(sheet_interval="table"); /*Changing the sheet interval triggers the new sheet to start*/
ods tagsets.excelxp options(sheet_interval="none" /*Change the interval back to none to keep all part b tables on the same sheet*/
embedded_titles = 'yes' /*Titles will appear in the worksheet, not as headers, which is the default.*/
			sheet_name="Primary DX Summary" /*First sheet will contain part A data*/
			skip_space='3,0,1,1,1' /*Spacing between tables*/
		/*	orientation='landscape' /*When printing, default to langscape orientation*/
			FitToPage = 'yes' 
			Pages_FitWidth = '1' /*Fit to 1 page across.*/
			Pages_FitHeight = '100' /*allow a sheet to be multiple pages long*/
			autofit_height='Yes' /*Excel determines row height*/
);




/*Primary diagnosis code summary*/
proc report data=work.prime_dx_summary3_&x; /*define the table to export*/
column CHI_DRG_DIAGNOSIS_RELATED_GROUP_ Primary_DX_Code Description Claim_COUNT Bene_Count amount_paid;
title1 height=17pt bold underline=1 'Primary Diagnosis Code Report'; /*Insert sheet title here*/

define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=center borderleftwidth=5 width=1.8in } ;
define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=left width=2in} ;

define Primary_DX_Code / display
	style(column)={tagattr='Format:@'}; /*Retain formatting */

define CLAIM_COUNT /display style(column) = {just=center width=2in } 'Claims';
define CLAIM_COUNT /display style(column) = {just=left width=2in} ;

define Bene_Count /display style(column) = {just=center width=2in } 'Beneficiaries';
define Bene_Count /display style(column) = {just=left width=2in} ;
run;
/****************************************/
/************ SHEET 5:Other DX ********/
/****************************************/

ods tagsets.excelxp options(sheet_interval="table"); /*Changing the sheet interval triggers the new sheet to start*/
ods tagsets.excelxp options(sheet_interval="none" /*Change the interval back to none to keep all part b tables on the same sheet*/
embedded_titles = 'yes' /*Titles will appear in the worksheet, not as headers, which is the default.*/
			sheet_name="Other DX Summary" /*First sheet will contain part A data*/
			skip_space='3,0,1,1,1' /*Spacing between tables*/
		/*	orientation='landscape' /*When printing, default to langscape orientation*/
			FitToPage = 'yes' 
			Pages_FitWidth = '1' /*Fit to 1 page across.*/
			Pages_FitHeight = '100' /*allow a sheet to be multiple pages long*/
			autofit_height='Yes' /*Excel determines row height*/
);


/*Primary other diagnosis code summary*/
proc report data=work.OTHER_DX_LONG2_&x; /*define the table to export*/
column CHI_DRG_DIAGNOSIS_RELATED_GROUP_ OTHER_DX_CODE Description CLAIM_COUNT Bene_Count;
title1 height=17pt bold underline=1 'All Other Diagnosis Code Report'; /*Insert sheet title here*/

define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=center borderleftwidth=5 width=1.8in } ;
define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=left width=2in} ;

define OTHER_DX_CODE / display
	style(column)={tagattr='Format:@'}; /*Retain formatting */


define claim_count /display style(column) = {just=center width=1.8in } ;
define claim_count /display style(column) = {just=left width=2in} ;

define Bene_Count /display style(column) = {just=center width=1.8in } 'Beneficiaries' ;
define Bene_Count /display style(column) = {just=left width=2in} ;
run;


/****************************************/
/************ SHEET 6:Provider Summary***/
/****************************************/

ods tagsets.excelxp options(sheet_interval="table"); /*Changing the sheet interval triggers the new sheet to start*/
ods tagsets.excelxp options(sheet_interval="none" /*Change the interval back to none to keep all part b tables on the same sheet*/
embedded_titles = 'yes' /*Titles will appear in the worksheet, not as headers, which is the default.*/
			sheet_name="Provider Summary" /*First sheet will contain part A data*/
			skip_space='3,0,1,1,1' /*Spacing between tables*/
		/*	orientation='landscape' /*When printing, default to langscape orientation*/
			FitToPage = 'yes' 
			Pages_FitWidth = '1' /*Fit to 1 page across.*/
			Pages_FitHeight = '100' /*allow a sheet to be multiple pages long*/
			autofit_height='Yes' /*Excel determines row height*/
);


/*Provider summary report*/
proc report data=work.PROVIDERS_&x; /*define the table to export*/
title1 height=17pt bold underline=1 'Provider Summary Report'; /*Insert sheet title here*/

define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(header) = {just=center width=1.8in } ;
define CHI_DRG_DIAGNOSIS_RELATED_GROUP_ /display style(column) = {just=left width=2in} ;

define BP_BILLING_PROV_NUM_NPI /display style(header) = {just=center width=1.8in } ;
define BP_BILLING_PROV_NUM_NPI /display style(column) = {just=left width=2in} ;

define BP_BILLING_PROV_NUM_oscar /display style(header) = {just=center width=1.8in } ;
define BP_BILLING_PROV_NUM_OSCAR /display style(column) = {just=left width=2in} ;

define contract /display style(header) = {just=center width=1.8in } ;
define contract /display style(column) = {just=left width=2in} ;

define FPX_FACILITY_PROV_NPICS_NAME_LEG /display style(header) = {just=center width=1.8in } 'Legal Name';
define FPX_FACILITY_PROV_NPICS_NAME_LEG /display style(column) = {just=left width=2in} ;


define CITY /display style(header) = {just=center width=1.5in } 'City';
define CITY /display style(column) = {just=left width=1.5in} ;

define STATE /display style(header) = {just=center width=1in } 'State';
define STATE /display style(column) = {just=left width=1in} ;


define ZIP /display style(header) = {just=center width=1in } 'Zip';
define ZIP /display style(column) = {just=left width=1in} ;

define claim_count /display style(header) = {just=center width=2in } '# Claims';
define claim_count /display style(column) = {just=left width=2in} ;

define beneficiaries /display style(header) = {just=center width=2in } ;
define beneficiaries /display style(column) = {just=left width=2in} ;

define denied_claims /display style(header) = {just=center width=2in }'Claims Denied' ;
define denied_claims /display style(column) = {just=left width=2in} ;

define paid_claims /display style(header) = {just=center width=2in }'Paid Denied' ;
define paid_claims /display style(column) = {just=left width=2in} ;

define rejected_claims /display style(header) = {just=center width=2in }'Rejected Denied' ;
define rejected_claims /display style(column) = {just=left width=2in} ;

define amount_paid /display style(header) = {just=center width=2in }'Amt_Paid' ;
define amount_paid /display style(column) = {just=left width=2in} ;
run;


/****************************************/
/************ SHEET 7:LOS Summary***/
/****************************************/

ods tagsets.excelxp options(sheet_interval="table"); /*Changing the sheet interval triggers the new sheet to start*/
ods tagsets.excelxp options(sheet_interval="none" /*Change the interval back to none to keep all part b tables on the same sheet*/
embedded_titles = 'yes' /*Titles will appear in the worksheet, not as headers, which is the default.*/
			sheet_name="LOS" /*First sheet will contain part A data*/
			skip_space='3,0,1,1,1' /*Spacing between tables*/
		/*	orientation='landscape' /*When printing, default to langscape orientation*/
			FitToPage = 'yes' 
			Pages_FitWidth = '1' /*Fit to 1 page across.*/
			Pages_FitHeight = '100' /*allow a sheet to be multiple pages long*/
			autofit_height='Yes' /*Excel determines row height*/
);


proc print data=work.LOS_&x noobs; /*define the table to export*/
var _all_;
title1 height=17pt bold underline=1 'Length of Stay Summary Report'; /*Insert sheet title here*/
run;

/****************************************/
/************ SHEET 8:TOB Summary***/
/****************************************/

ods tagsets.excelxp options(sheet_interval="table"); /*Changing the sheet interval triggers the new sheet to start*/
ods tagsets.excelxp options(sheet_interval="none" /*Change the interval back to none to keep all part b tables on the same sheet*/
embedded_titles = 'yes' /*Titles will appear in the worksheet, not as headers, which is the default.*/
			sheet_name="tob" /*First sheet will contain part A data*/
			skip_space='3,0,1,1,1' /*Spacing between tables*/
		/*	orientation='landscape' /*When printing, default to langscape orientation*/
			FitToPage = 'yes' 
			Pages_FitWidth = '1' /*Fit to 1 page across.*/
			Pages_FitHeight = '100' /*allow a sheet to be multiple pages long*/
			autofit_height='Yes' /*Excel determines row height*/
);


proc print data=work.tob_summary_&x noobs label; /*define the table to export*/
var TOB/style(data)={width= 75 just=c} style(header)={width=75 just=c};
var CHI_TOB_TYPE_of_Bill_Cd_Desc/style(data)={width= 150 just=c} style(header)={width=150just=c};
var CHI_DRG_DIAGNOSIS_RELATED_GROUP_/style(data)={width= 75 just=c} style(header)={width=75 just=c};
var claim_count/ style(data)={width= 75 just=c} style(header)={width=75 just=c};
var beneficiaries/ style(data)={width= 100 just=c} style(header)={width=100 just=c};
var amount_paid/ style(data)={width= 20 just=c} style(header)={width=20 just=c};

label TOB = 'Type of Bill'
	  CHI_TOB_TYPE_of_Bill_Cd_Desc = 'TOB Description'
      CHI_DRG_DIAGNOSIS_RELATED_GROUP_='DRG'
      claim_count= '# Claims'
       Amount_Paid='Amt Paid';
title1 height=17pt bold underline=1 'Type of Bill Summary Report For DRG'; /*Insert sheet title here*/
title2 height=12pt '(Sorted by Amount Paid Descending Order)';
run;





/*Close the tagset and exit ods*/
ods tagsets.excelxp close;
ods _all_ close; 







%mend;



/*Loop over the list of DRGs that were created at the beginning of the code*/

%macro loopit(mylist);
    %let else=;
   %let n = %sysfunc(countw(&mylist)); /*let n=number of codes in the list*/
    data ;
   %do I=1 %to &n;
      %let val = %scan(&mylist,&I); /*Let val= the ith code in the list*/
    %end;

   %do j=1 %to &n;
      %let val = %scan(&mylist,&j); /*Let val= the jth code in the list*/

/*Run over all drgs stored in &val for J8*/
%runtab(&val,J8);

/*Run over all drgs stored in &val for J5*/
%runtab(&val,J5);

   %end;
   run;
%mend;

/*Loops over all drgs */
%loopit(&varlist)
