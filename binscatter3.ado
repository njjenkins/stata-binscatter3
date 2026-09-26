*! binscatter3: local fork of binscatter2 v0.91 (19jan2023, Michael Droste) adding the line45 option
*===============================================================================
* Program: binscatter3.ado (fork of binscatter2.ado; adds line45 option for a dashed gray 45-degree line)
* Purpose: New functionality and efficiency improvements for binscatter.
* Author:  Michael Droste
* Version: 0.91 (19jan2023)
* Credits: This program was made possible due to the collective efforts of a 
*          handful of Stata superstars, among them:
*           - Michael Stepner, who wrote the original binscatter (with 
*             contributions from Jessica Laird).
*           - Sergio Correa, who developed ftools and proved that hash tables
*             could be used to speed up a number of Stata routines.
*           - Mauricio Caceres Bravo, who produced gtools, Correa's ftools in 
*             hyper-efficient compiled C, which is used to make the computation
*             of quantiles and means/medians within quantiles much more efficient.
* License: You are free to do whatever you want with this program.
*===============================================================================

program define binscatter3, eclass 
version 12.1
	
syntax varlist(min=2 numeric) [if] [in] [aweight fweight], ///
[ ///
	by(varname) ///
	Nquantiles(integer 20) ///
	GENxq(name) ///
	discrete ///
	xq(varname numeric) ///
	MEDians ///
	CONTROLs(varlist numeric ts fv) ///
	Absorb(varlist) ///
	noAddmean ///
	LINEtype(string) ///
	rd(numlist ascending) ///
	reportreg ///
	noplot nograph ///
	COLors(string asis) ///
	MColors(string asis) ///
	LColors(string asis) ///
	Msymbols(string) ///
	savegraph(string) ///
	savedata(string) ///
	quantiles(numlist integer ascending) ///
	stdevs(integer -1) ///
	nodofile ///
	fast ///
	altcontrols ///
	plotraw /// 
	replace ///
	vce(string) ///
	robust ///
	nofastxtile ///
	randvar(varname numeric) ///
	randcut(real 1) ///
	randn(integer -1) ///
	line45 ///
	/* LEGACY OPTIONS */ nbins(integer 20) create_xq x_q(varname numeric) symbols(string) method(string) unique(string) ///
	*]

set more off

* noplot/nograph/nodofile are stored by syntax in locals `plot', `graph', and `dofile'
if ("`plot'`graph'"!="") local noplot noplot
if ("`dofile'"!="") local nodofile nodofile

*---------------------------------------------------------------------------
* Check prerequisite packages
*---------------------------------------------------------------------------

* User MUST have gtools installed (recent enough to have fasterxtile)
cap which fasterxtile
local a1 = _rc
cap which gcollapse
local a2 = _rc
if `a1'!=0 | `a2'!=0 {
	di as error "Error: Must have gtools installed to use binscatter3"
	di as error " See the gtools github repo: https://github.com/mcaceresb/stata-gtools"
	exit 199
}

* Optional: check to see if user has reghdfe, and set a flag if so
cap which reghdfe
local has_reghdfe = _rc == 0
	
*---------------------------------------------------------------------------
* Check compatibility with legacy binscatter options
*---------------------------------------------------------------------------

* Can't specify both nbins() (legacy) and nquantiles() options
if `nbins'!=20 {
	if `nquantiles'!=20 {
		di as error "Cannot specify both nquantiles() and nbins(): both are the same option, nbins is supported only for backward compatibility."
		exit 198
	}
	di as text "NOTE: legacy binscatter option nbins() has been renamed nquantiles(), and is supported only for backward compatibility."
	local nquantiles = `nbins'
}
	
* Can't specify both create_xq() (legacy) and genxq() options
if "`create_xq'"!="" {
	if "`genxq'"!="" {
		di as error "Cannot specify both genxq() and create_xq: both are the same option, create_xq is supported only for backward compatibility."
		exit 198
	}
	di as text "NOTE: legacy binscatter option create_xq has been renamed genxq(), and is supported only for backward compatibility."
	local genxq = "q_"+word("`varlist'",-1)
}
	
* Can't specify both x_q() (legacy) and xq() options
if "`x_q'"!="" {
	if "`xq'"!="" {
		di as error "Cannot specify both xq() and x_q(): both are the same option, x_q() is supported only for backward compatibility."
		exit 198
	}
	di as text "NOTE: legacy binscatter option x_q() has been renamed xq(), and is supported only for backward compatibility."
	local xq `x_q'
}
	
* Can't specify symbols() (legacy) and msymbols() options
if "`symbols'"!="" {
	if "`msymbols'"!="" {
		di as error "Cannot specify both msymbols() and symbols(): both are the same option, symbols() is supported only for backward compatibility."
		exit 198
	}
	di as text "NOTE: legacy binscatter option symbols() has been renamed msymbols(), and is supported only for backward compatibility."
	local msymbols `symbols'
}
	
* Can't use line type noline (legacy), now called none
if "`linetype'"=="noline" {
	di as text "NOTE: legacy binscatter line type 'noline' has been renamed 'none', and is supported only for backward compatibility."
	local linetype none
}
	
* Can't use method() legacy option
if "`method'"!="" {
	di as text "NOTE: method() is no longer a recognized option in binscatter3 and will be ignored. binscatter3 now always uses the fastest method without a need for two instances"
}
	
* Can't use unique() legacy option
if "`unique'"!="" {
	di as text "NOTE: unique() is no longer a recognized option in binscatter3 and will be ignored. binscatter3 now considers the x-variable discrete if it has fewer unique values than nquantiles()"
}

* Can't use nofastxtile() legacy option
if "`nofastxtile'"!="" {
	di as text "NOTE: nofastxtile is no longer a recognized option in binscatter3 and will be ignored. binscatter3 uses gtools to compute quantiles, not fastxtile."
}

* Can't use randcut, randvar legacy options
if "`randcut'"!="1" | "`randvar'"!="" | "`randn'"!="-1" {
	di as text "NOTE: randcut, randvar, and randn are no longer recognized options in binscatter3 and will be ignored."
}

*-------------------------------------------------------------------------------
* Error checking
*-------------------------------------------------------------------------------

* Set default linetype and check valid
if ("`linetype'"=="") local linetype lfit
else if !inlist("`linetype'","connect","lfit","qfit","expfit","logfit","none") {
	di as error "Error: linetype() invalid: must be connect, lfit, qfit, logfit, expfit, or none"
	exit 198
}

* Cannot specify more than one of genxq(), xq(), and discrete
if ("`genxq'"!="" & ("`xq'"!="" | "`discrete'"!="")) | ("`xq'"!="" & "`discrete'"!="") {
	di as error "Error: Cannot specify more than one of genxq(), xq(), and discrete simultaneously."
	exit 198
}

* Check that variable name specified by genxq() doesn't exist if that option is specified
if "`genxq'"!="" {
	confirm new variable `genxq'
}
	
* Make sure xq contains only positive integers
if "`xq'"!="" {
	capture assert `xq'==int(`xq') & `xq'>0
	if _rc!=0 {
		di as error "Error: The xq() option must contain only positive integers."
		exit 198
	}
	if ("`controls'`absorb'"!="") {
		di as text "Warning: xq() is specified in combination with controls() or absorb()."
		di as text "  Note that binning takes places after residualization, so the xq variable should contain bins of the residuals."
	}
}

* Check to make sure nquantiles not used with discrete or xq options
if `nquantiles'!=20 & ("`xq'"!="" | "`discrete'"!="") {
	di as error "Error: Cannot specify nquantiles in combination with discrete or an xq variable."
	exit 198
}

* Check that reportreg is not used with linetype(none) option
if "`reportreg'"!="" & !inlist("`linetype'","lfit","qfit","logfit","expfit") {
	di as error "Error: Cannot specify 'reportreg' when no fit line is being created."
	exit 198
}

* Display a warning if nodofile used without savedata
if "`nodofile'"!="" & "`savedata'"=="" {
	di as text "Warning: The nodofile option was specified, but savedata was not. This is harmless, but a weird choice!"
}

* Parse savedata() into a data file (.csv or .dta) and a do-file sharing its base name
if `"`savedata'"'!="" {
	local savedata_base `"`savedata'"'
	local dataextension ".csv"
	if regexm(`"`savedata'"',"\.[a-zA-Z0-9]+$") {
		local ext = lower(regexs(0))
		if inlist("`ext'",".csv",".dta") {
			local dataextension "`ext'"
			local savedata_base = substr(`"`savedata'"',1,length(`"`savedata'"')-length("`ext'"))
		}
		else di as text "Warning: unrecognized file extension (`ext') in savedata(). Saving as a CSV instead."
	}
	local savedata_file `"`savedata_base'`dataextension'"'
	local savedata_do   `"`savedata_base'.do"'
}

* If replace is not specified and savegraph/savedata are, make sure files don't exist
if "`replace'"=="" {
	if `"`savegraph'"'!="" {
		if regexm(`"`savegraph'"',"\.[a-zA-Z0-9]+$") confirm new file `"`savegraph'"'
		else confirm new file `"`savegraph'.gph"'
	}
	if `"`savedata'"'!="" {
		confirm new file `"`savedata_file'"'
		if "`nodofile'"=="" confirm new file `"`savedata_do'"'
	}
}

* No display: Make sure that noplot only used if savedata is specified
if "`noplot'"!="" & "`savedata'"=="" {
	di "Warning: Doesn't make sense to use noplot option without savedata."
	di "Ignoring noplot (drawing binscatter)."
	local noplot
}

* Can't save a graph that isn't drawn
if "`noplot'"!="" & `"`savegraph'"'!="" {
	di as error "Error: Cannot specify savegraph() with noplot/nograph."
	exit 198
}

* Make sure quantiles are between 0 and 100, and there arent more than 2
local num_quantiles = 0
foreach v in `quantiles' {
	if ~inrange(`v',0,100) {
		di as error "Error: quantiles must be between 0 and 100 (`v' is not)"
		exit 198
	}
	local num_quantiles = `num_quantiles' + 1
}
if `num_quantiles'>2 {
	di as error "Error: Maximum of two quantiles allowed"
	exit 198
}

* Quantiles can't be specified with by or multiple dependent vars currently,
* Why? Too many lines floating around
if "`quantiles'"!="" {
	if wordcount("`varlist'")>2 {
		di as error "Error: Can't use quantiles() option with more than one dependent variable."
		exit 198
	}
	if "`by'"!="" {
		di as error "Error: Can't use quantiles() option with by groups."
		exit 198
	}
}

* plotraw only supports a single dependent variable
if "`plotraw'"!="" & wordcount("`varlist'")>2 {
	di as error "Error: Cannot use plotraw option with more than one dependent variable."
	exit 198
}

* Specify either quantiles OR stdevs, not both
if "`quantiles'"!="" & `stdevs'!=-1 {
	di as error "Error: can't specify both stdevs() and quantiles(), choose one."
	exit 198
}


* FOR NOW, alternative binning procedure doesn't work with controls
* Why? I have a problem set due tomorrow and can't fix this tonight
if "`quantiles'"!="" {
	if wordcount("`varlist'")>2 {
		di as error "Error: Can't use quantiles() option with more than one dependent variable."
		exit 198
	}
	if "`by'"!="" {
		di as error "Error: Can't use quantiles() option with by groups."
		exit 198
	}
}

*-------------------------------------------------------------------------------
* Option parsing
*-------------------------------------------------------------------------------

* Create convenient weight local
if ("`weight'"!="") local wt [`weight'`exp']

* VCE for the fit-line regressions (affects only the standard errors shown by reportreg)
if "`robust'"!="" & `"`vce'"'=="" local vce robust
if `"`vce'"'!="" {
	local vceopt vce(`vce')
	if regexm(`"`vce'"',"^cl[a-z]*[ ]+(.+)$") local clustervar = regexs(1)
}

* Mark sample (reflects the if/in conditions, and includes only nonmissing observations)
marksample touse
markout `touse' `by' `xq' `controls' `absorb' `clustervar', strok

* Create a temporary ID for later merges
if "`genxq'"!="" {
	tempvar temp_id
	gen `temp_id' = _n
}

* Preserve dataset before we drop and collapse stuff
preserve

* Try to speed things up
qui keep if `touse'

* Count sample - XX is this valid?
qui count
local samplesize  = r(N)

* Parse varlist into y-vars and x-var
local x_var  = word("`varlist'",-1)
local y_vars = regexr("`varlist'"," `x_var'$","")
local ynum   = wordcount("`y_vars'")

* Check number of unique byvals & create local storing byvals
if "`by'"!="" {
	local byvarname `by'
	capture confirm numeric variable `by'
	if _rc {
		* by-variable is string => generate a numeric version
		tempvar by
		tempname bylabel
		egen `by'=group(`byvarname'), lname(`bylabel')
	}	
	local bylabel `:value label `by'' /*catch value labels for numeric by-vars too*/ 	
	tempname byvalmatrix
	qui tab `by' if `touse', nofreq matrow(`byvalmatrix')	
	local bynum = r(r)
	forvalues i=1/`bynum' {
		local byvals `byvals' `=`byvalmatrix'[`i',1]'
	}
}
else local bynum = 1

* Parse absorb and regress type
if `"`absorb'"'!="" {
	local num_fes = 0
	foreach v of varlist `absorb' {
		local num_fes = `num_fes' + 1
	}
	*noi di "Num fes: `num_fes'"
	local absorb "absorb(`absorb')"
	local regtype "areg"
	if `num_fes' > 1 {
		local regtype "reghdfe"
		cap which reghdfe
		if _rc>0 {
			di as error "Error: You specified more than 1 fixed effect in absorb(), but don't have reghdfe installed."
			di as error "Please install the reghdfe package from SSC or GitHub to absorb multi-way fixed effects with binscatter3."
			exit 199
		}
	}
	if `num_fes'== 1 {
		cap which reghdfe
		if _rc==0 {
			local regtype reghdfe
		}
		else {
			di "Warning: reghdfe not installed. binscatter3 may be faster when you use absorb() with reghdfe installed."
		}
	}
}
if `"`absorb'"'=="" {
	local regtype "_regress"
	local regopts "noheader notable"
}

*-------------------------------------------------------------------------------
* Residualize variables, if controls() or absorb() specified
*-------------------------------------------------------------------------------


* If doing old-school binscatter, residualizing y and x wrt controls (Frisch-Waugh logic)
if "`altcontrols'"=="" {

	* If controls() or absorb() are specified...
	if `"`controls'`absorb'"'!="" quietly {

		* Residualize x variable
		tempvar residvar
		if "`regtype'"=="reghdfe" {
			`regtype' `x_var' `controls' `wt', `absorb' `regopts' resid(`residvar')
		}
		else {
			`regtype' `x_var' `controls' `wt', `absorb' `regopts'
			predict `residvar' if e(sample), residuals
		}
		if "`addmean'"!="noaddmean" {
			summarize `x_var' `wt' if `touse', meanonly
			replace `residvar'=`residvar'+r(mean)
		}
		replace `x_var' = `residvar'
		local x_r `x_var'

		* Residualize y variables
		foreach yvar of varlist `y_vars' {
			tempvar residvar
			if "`regtype'"=="reghdfe" {
				`regtype' `yvar' `controls' `wt', `absorb' `regopts' resid(`residvar')
			}
			else {
				`regtype' `yvar' `controls' `wt', `absorb' `regopts'
				predict `residvar' if e(sample), residuals
			}
			if "`addmean'"!="noaddmean" {
				summarize `yvar' `wt' if `touse', meanonly
				replace `residvar' = `residvar'+r(mean)
			}	
			replace `yvar' = `residvar'
			*noi di "y_vars_r: `y_vars_r'"
			*noi di "residvar: `residvar'"
			local y_vars_r `y_vars_r' `residvar'
		}

	}

}

local x_r `x_var'
local y_vars_r `y_vars'

*-------------------------------------------------------------------------------
* Generate x-bin
*-------------------------------------------------------------------------------

qui keep if ~mi(`x_r')
qui foreach v of local y_vars_r {
	keep if ~mi(`v')
}

* When xq is not specified...
if "`xq'"=="" {
	* When discrete is not specified...
	if "`discrete'"=="" {
		if ("`genxq'"!="") local xq `genxq'
		else tempvar xq
		fasterxtile `xq' = `x_r' `wt', nq(`nquantiles')	
	}
	* If discrete is specified...
	if "`discrete'"!="" {
		if ("`genxq'"!="") local xq `genxq'
		else tempvar xq
		gen `xq' = `x_r'
	}
}


* When genxq is specified, save them out with temporary id's to be merged on at end
* XX this is inefficient and not very elegant
if "`genxq'"!="" {
	* Save present data as a temporary file
	tempfile temp_file_1
	qui save "`temp_file_1'"
	* Keep only temp id and xq, then save as temporary file we merge on at end
	keep `temp_id' `xq'
	tempfile temp_file_2
	qui save "`temp_file_2'"
	* Load present data again
	qui use "`temp_file_1'"
}		

*----------------------------------------------------------------------------------
* Alternative residualization
*----------------------------------------------------------------------------------

* If doing alternative binning strategy...
if "`altcontrols'"!="" {

	* Residualize y variables
	local y_vars_r 
	qui foreach yvar of varlist `y_vars' {
		tempvar yhat
		`regtype' `yvar' i.`xq' `controls' `wt', `absorb' `regopts'
		predict `yhat' if e(sample), xb
		replace `yvar' = `yhat'
		if "`controls'"!="" {
			foreach v of varlist `controls' {
				qui replace `yvar' = `yvar' - _b[`v']*`v'
			}
		}
		local y_vars_r `y_vars_r' `yvar'
	}

}

*-------------------------------------------------------------------------------
* Run regressions for fit lines
*-------------------------------------------------------------------------------

if ("`reportreg'"=="") local reg_verbosity "quietly"

if inlist("`linetype'","lfit","qfit","logfit","expfit") `reg_verbosity' {

	* If doing a quadratic fit, generate a quadratic term in x
	if "`linetype'"=="qfit" {
		tempvar x_r2
		gen `x_r2' = `x_r'^2
	}

	* If doing a logarithmic fit, generate a quadratic term in x
	if "`linetype'"=="logfit" {
		tempvar x_r_log
		gen `x_r_log' = log(`x_r')
	}

	* If doing an exponential fit, generate an exponential term in x
	if "`linetype'"=="expfit" {
		tempvar x_r_exp
		gen `x_r_exp' = exp(`x_r')
	}

	* If doing polynomial fit, generatic polynomial terms in x
	* xx

	* Generate a local holding regressors
	local regressor_list `x_r'
	if "`linetype'"=="qfit" local regressor_list `x_r' `x_r2'
	if "`linetype'"=="logfit" local regressor_list `x_r_log'
	if "`linetype'"=="expfit" local regressor_list `x_r_exp'
		
	* Create matrices to hold regression results
	tempname e_b_temp
	forvalues i=1/`ynum' {
		tempname y`i'_coefs
	}
		
	* LOOP over by-vars
	local counter_by = 1
	if "`by'"=="" local noby = "noby"
	foreach byval in `byvals' `noby' {
		
		* LOOP over rd intervals
		tokenize "`rd'"
		local counter_rd = 1	
				
		while ("`1'"!="" | `counter_rd'==1) {

			* Display text headers
			if "`reportreg'"!="" {
				di "{txt}{hline}"
				if "`by'"!="" {
					if ("`bylabel'"=="") di "-> `byvarname' = `byval'"
					else {
						di "-> `byvarname' = `: label `bylabel' `byval''"
					}
				}
				if "`rd'"!="" {
					if `counter_rd'==1 di "RD: `x_var'<=`1'"
					else if "`2'"!="" di "RD: `x_var'>`1' & `x_var'<=`2'"
					else di "RD: `x_var'>`1'"
				}
			}
				
			* Set conditions on reg
			local conds `touse'
			if "`by'"!=""  local conds `conds' & `by'==`byval'
			if "`rd'"!="" {
				if `counter_rd'==1 local conds `conds' & `x_r'<=`1'
				else if "`2'"!="" local conds `conds' & `x_r'>`1' & `x_r'<=`2'
				else local conds `conds' & `x_r'>`1'
			}

			* Regressions for each dependent variable
			local counter_depvar=1
			foreach depvar of varlist `y_vars_r' {

				* Display text headers
				if `ynum'>1 {
					if "`controls'`absorb'"!="" local depvar_name : var label `depvar'
					else local depvar_name `depvar'
					di as text "{bf:y_var = `depvar_name'}"
				}

				* Perform regressions
				if "`reg_verbosity'"=="quietly" {
					capture reg `depvar' `regressor_list' `wt' if `conds', noheader notable `vceopt'
				}
				else {
					capture noisily reg `depvar' `regressor_list' `wt' if `conds', `vceopt'
				}

				* Store results (a fit line with no observations gets missing coefficients and is not drawn)
				if _rc==0 matrix `e_b_temp' = e(b)
				else if _rc==2000 {
					noi di as text "Note: no observations for one of the fit lines; it will not be drawn. Add 'reportreg' for more info."
					if "`linetype'"=="qfit" matrix `e_b_temp' = J(1,3,.)
					else matrix `e_b_temp' = J(1,2,.)
				}
				else {
					exit _rc
				}

				* Relabel matrix row
				if ("`by'"!="") matrix roweq `e_b_temp' = "by`counter_by'"
				if ("`rd'"!="") matrix rownames `e_b_temp' = "rd`counter_rd'"
				else matrix rownames `e_b_temp' = "="

				* Save to y_var matrix
				if `counter_by'==1 & `counter_rd'==1 {
					matrix `y`counter_depvar'_coefs' = `e_b_temp'
				}
				else {
					matrix `y`counter_depvar'_coefs' = `y`counter_depvar'_coefs' \ `e_b_temp'
				}
				local ++counter_depvar
			}

			* Increment counter for RDs
			if `counter_rd'!=1 mac shift
			local ++counter_rd
		}

		* Increment counter for by-group
		local ++counter_by
	}

	* Relabel matrix column names (order matches regressor_list)
	forvalues i=1/`ynum' {
		if "`linetype'"=="lfit" {
			matrix colnames `y`i'_coefs' = "`x_var'" "_cons"
		}
		else if "`linetype'"=="qfit" {
			matrix colnames `y`i'_coefs' = "`x_var'" "`x_var'^2" "_cons"
		}
	}
}	

*-------------------------------------------------------------------------------
* Compute means of x and y within each bin
* KEY OUTPUT: `y1_scatterpts' for each 1,...N depvars is a N_BINS x 2 matrix
*             containing binned x vals in col 1 and binned y vals in col 2
*-------------------------------------------------------------------------------

* Define type of collapse
local collapsetype mean
if "`medians'"!="" local collapsetype median

* If quantiles specified: define macro to pass into gcollapse
if "`quantiles'"!="" {
	local current_quantile 1
	foreach v in `quantiles' {
		local q`current_quantile' = `v'
		local current_quantile = `current_quantile' + 1
	}
	local quantiles_opt "(p`q1') p`q1'=`y_vars_r' (p`q2') p`q2'=`y_vars_r'"
	local quantile_vars p`q1' p`q2'
}

* If stdevs specified: define macro to pass into gcollapse
if `stdevs'!=-1 {
	tempvar sd
	local quantiles_opt "(sd) `sd' =`y_vars_r'"
}

*---------------------------------------------------
* Handle case with no by-groups
*---------------------------------------------------

* If no by groups....
if "`by'"=="" {

	* Collapse residualized y vars and x var within each x bin
	qui drop if `xq'==.

	* If plotraw specified, set aside the raw points to append before graphing
	if "`plotraw'"!="" {
		tempvar raw_x raw_y
		tempfile fulldata rawpts
		qui save "`fulldata'"
		keep `x_r' `y_vars_r'
		rename `x_r' `raw_x'
		rename `y_vars_r' `raw_y'
		qui save "`rawpts'"
		qui use "`fulldata'", clear
	}

	gcollapse (`collapsetype') `y_vars_r' `x_r' `quantiles_opt' `wt', by(`xq') fast

	* Make matrix containing mean x and mean y within each bin for each y var
	local counter_depvar=0
	foreach depvar of varlist `y_vars_r' {
		local ++counter_depvar
		tempname y`counter_depvar'_scatterpts
		mkmat `x_r' `depvar', mat(`y`counter_depvar'_scatterpts')
	}

	* If quantiles specified, create a macro
	if "`quantiles'"!="" {
		if `c(stata_version)' >= 15.0 local opacity %40
		local quantile_macro (rarea p`q2' p`q1' `x_r', color(gs12`opacity'))
	}

	* If stdevs specified
	if `stdevs'>-1 {
		if `c(stata_version)' >= 15.0 local opacity %40
		tempvar sd_ub sd_lb
		gen `sd_ub' = `y_vars_r' + `stdevs'*`sd'
		gen `sd_lb' = `y_vars_r' - `stdevs'*`sd'
		local quantile_macro (rarea `sd_ub' `sd_lb' `x_r', color(gs12`opacity'))
	}

}

*---------------------------------------------------
* Handle case with by-groups
*---------------------------------------------------

* If by groups specified...
if "`by'"!="" {

	* Preserve initial dataset
	tempfile t1
	qui save "`t1'"

	* Start a counter of by groups
	local by_counter = 0

	* For each by-group...
	qui foreach byval in `byvals' `noby' {

		local by_counter = `by_counter' + 1

		* Keep only obs in current by-group
		qui keep if `by'==`byval'

		* Collapse residualized y vars and x var within each x bin
		qui drop if `xq'==.
		gcollapse (`collapsetype') `y_vars_r' `x_r' `wt', by(`xq') fast

		* Make matrix containing mean x and mean y within each bin for each y var
		local counter_depvar=0
		foreach depvar of varlist `y_vars_r' {
			local ++counter_depvar
			tempname y`counter_depvar'_scatterpts bypts`by_counter'_`counter_depvar'
			mkmat `x_r' `depvar', mat(`bypts`by_counter'_`counter_depvar'')
		}

		* Restore original dataset for next by group
		use "`t1'", clear
	}

	* Concatenate by-group matrices side by side, padding with missing rows where
	* by-groups have different numbers of bins
	tempname pad
	forval i=1/`ynum' {
		mat `y`i'_scatterpts' = `bypts1_`i''
		if `by_counter'>1 {
			forval j=2/`by_counter' {
				local rows_1 = rowsof(`y`i'_scatterpts')
				local cols_1 = colsof(`y`i'_scatterpts')
				local rows_2 = rowsof(`bypts`j'_`i'')
				* If current by group has fewer rows than mat, append current by group with empty rows
				if `rows_2' < `rows_1' {
					mat `pad' = J(`=`rows_1'-`rows_2'',2,.)
					mat `bypts`j'_`i'' = `bypts`j'_`i'' \ `pad'
				}
				* If current by group has more rows than mat, append mat with empty rows
				if `rows_2' > `rows_1' {
					mat `pad' = J(`=`rows_2'-`rows_1'',`cols_1',.)
					mat `y`i'_scatterpts' = `y`i'_scatterpts' \ `pad'
				}
				mat `y`i'_scatterpts' = `y`i'_scatterpts',`bypts`j'_`i''
			}
		}
	}

}

*-------------------------------------------------------------------------------
* Prepare scatter plot options
*-------------------------------------------------------------------------------

* If rd is specified: prepare xline parameters
if "`rd'"!="" {
	foreach xval in "`rd'" {
		local xlines `xlines' xline(`xval', lpattern(dash) lcolor(gs8))
	}
}

* Fill colors if missing
if `"`colors'"'=="" local colors navy maroon forest_green dkorange teal cranberry ///
	lavender khaki sienna emidblue emerald brown erose gold bluishgray
if `"`mcolors'"'=="" {
	if (`ynum'==1 & `bynum'==1 & "`linetype'"!="connect") local mcolors : word 1 of `colors'
	else local mcolors "`colors'"
}
if `"`lcolors'"'=="" {
	if (`ynum'==1 & `bynum'==1 & "`linetype'"!="connect") local lcolors : word 2 of `colors'
	else local lcolors `"`colors'"'
}
local num_mcolor = wordcount(`"`mcolors'"')
local num_lcolor = wordcount(`"`lcolors'"')

* Prepare connect & msymbol options
if ("`linetype'"=="connect") local connect "c(l)"
if "`msymbols'"!="" {
	local symbol_prefix "msymbol("
	local symbol_suffix ")"
}

*-------------------------------------------------------------------------------
* Define scatter points
*-------------------------------------------------------------------------------

* Prepare scatter plots
local c              = 0
local counter_series = 0
local counter_by     = 0
if ("`by'"=="") local noby="noby"

* For each by value
foreach byval in `byvals' `noby' {
	local ++counter_by
	local xind = `counter_by'*2 - 1
	local yind = `counter_by'*2
	local counter_depvar = 0

	* For each dependent variable
	foreach depvar of varlist `y_vars' {

		* Set up indices
		local ++counter_depvar
		local ++c
		local row  = 1
		local xval = `y`counter_depvar'_scatterpts'[`row',`xind']
		local yval = `y`counter_depvar'_scatterpts'[`row',`yind']

		* If quantiles defined
		local quantile_lower = `y`counter_depvar'_scatterpts'[`row',3]
		local quantile_upper = `y`counter_depvar'_scatterpts'[`row',4]

		if !missing(`xval',`yval') {
			local ++counter_series
			local scatters `scatters' (scatteri
			if ("`savedata'"!="") {
				if ("`by'"=="") local savedata_scatters `savedata_scatters' (scatter `depvar' `x_var'
				else local savedata_scatters `savedata_scatters' (scatter `depvar'_by`counter_by' `x_var'_by`counter_by'
			}
		}
		else continue
		while (`xval'!=. & `yval'!=.) {
			local scatters `scatters' `yval' `xval'	
			local ++row
			local xval = `y`counter_depvar'_scatterpts'[`row',`xind']
			local yval = `y`counter_depvar'_scatterpts'[`row',`yind']
		}

		* Add options
		local scatter_options `connect' mcolor("`: word `c' of `mcolors''") lcolor("`: word `c' of `lcolors''") `symbol_prefix'`: word `c' of `msymbols''`symbol_suffix'
		local scatters `scatters', `scatter_options')
		if "`savedata'"!="" local savedata_scatters `savedata_scatters', `scatter_options')

		* Store legend label for this series
		if "`by'"=="" local serieslab`counter_series' `depvar'
		else {
			if "`bylabel'"=="" local byvalname=`byval'
			else {
				local byvalname `: label `bylabel' `byval''
			}
			if (`ynum'==1) local serieslab`counter_series' `byvarname'=`byvalname'
			else local serieslab`counter_series' `depvar': `byvarname'=`byvalname'
		}
	}
}

* Build legend; plotraw's raw-data scatter is drawn first, shifting series numbers by one
* (the savedata do-file omits the raw data, so it uses unshifted numbers)
if ("`by'"=="" & `ynum'==1) {
	local legend_labels off
	local savedata_legend_labels off
}
else {
	local rawoffset = ("`plotraw'"!="")
	forvalues s=1/`counter_series' {
		local legend_labels `legend_labels' lab(`=`s'+`rawoffset'' `serieslab`s'')
		local order `order' `=`s'+`rawoffset''
		local savedata_legend_labels `savedata_legend_labels' lab(`s' `serieslab`s'')
		local savedata_order `savedata_order' `s'
	}
}

*-------------------------------------------------------------------------------
* Prepare fit lines
*-------------------------------------------------------------------------------

if inlist(`"`linetype'"',"lfit","qfit","logfit","expfit") {
	
	* c indexes which color is to be used
	local c = 0
	local rdnum = wordcount("`rd'") + 1
	tempname fitline_bounds
	if ("`rd'"=="") matrix `fitline_bounds' = .,.
	else matrix `fitline_bounds' = .,`=subinstr("`rd'"," ",",",.)',.

	* For each by-variable...
	local counter_by = 0
	if ("`by'"=="") local noby="noby"
	foreach byval in `byvals' `noby' {
		local ++counter_by

		* Set the column for the x-coords in the scatterpts matrix
		local xind = `counter_by'*2-1

		* Set the row to start seeking from. note: each time we seek a coeff, it should be from row (rd_num)(counter_by-1)+counter_rd
		local row0 = ( `rdnum' ) * (`counter_by' - 1)

		* For each dependent variable...
		local counter_depvar=0
		foreach depvar of varlist `y_vars_r' {
			local ++counter_depvar
			local ++c

			* Find lower and upper bounds for the fit line
			matrix `fitline_bounds'[1,1] = `y`counter_depvar'_scatterpts'[1,`xind']
			* (search up from the last row: xq() and discrete can have more bins than nquantiles)
			local fitline_ub_rindex = rowsof(`y`counter_depvar'_scatterpts')
			local fitline_ub=.
			while `fitline_ub'==. {
				local fitline_ub = `y`counter_depvar'_scatterpts'[`fitline_ub_rindex',`xind']
				local --fitline_ub_rindex
			}
			matrix `fitline_bounds'[1,`rdnum'+1] = `fitline_ub'

			* LOOP over rd intervals
			forvalues counter_rd=1/`rdnum' {

				* If fit type is linear, exponential, or logarithmic
				if inlist("`linetype'","lfit","logfit","expfit") {
					local coef_lin  = `y`counter_depvar'_coefs'[`row0'+`counter_rd',1]
					local coef_quad = 0
					local coef_cons = `y`counter_depvar'_coefs'[`row0'+`counter_rd',2]
				}

				* If fit type is quadratic
				else if "`linetype'"=="qfit" {
					local coef_lin  = `y`counter_depvar'_coefs'[`row0'+`counter_rd',1]
					local coef_quad = `y`counter_depvar'_coefs'[`row0'+`counter_rd',2]
					local coef_cons = `y`counter_depvar'_coefs'[`row0'+`counter_rd',3]
				}

				* Prepare local containing fit function
				if !missing(`coef_quad',`coef_lin',`coef_cons') {
					local leftbound  = `fitline_bounds'[1,`counter_rd']
					local rightbound = `fitline_bounds'[1,`counter_rd'+1]
					if "`linetype'"=="lfit" {
						local fits `fits' (function `coef_lin'*x+`coef_cons', range(`leftbound' `rightbound') lcolor("`: word `c' of `lcolors''"))
					}
					if "`linetype'"=="logfit" {
						local fits `fits' (function `coef_lin'*log(x)+`coef_cons', range(`leftbound' `rightbound') lcolor("`: word `c' of `lcolors''"))
					}
					if "`linetype'"=="expfit" {
						local fits `fits' (function `coef_lin'*exp(x)+`coef_cons', range(`leftbound' `rightbound') lcolor("`: word `c' of `lcolors''"))
					}
					if "`linetype'"=="qfit" {
						local fits `fits' (function `coef_quad'*x^2+`coef_lin'*x+`coef_cons', range(`leftbound' `rightbound') lcolor("`: word `c' of `lcolors''"))
					}
				}
			}
		}
	}
}

*-------------------------------------------------------------------------------
* Display graph
*-------------------------------------------------------------------------------

* Prepare y-axis title
if (`ynum'==1) local ytitle `y_vars'
else if (`ynum'==2) local ytitle : subinstr local y_vars " " " and "
else local ytitle : subinstr local y_vars " " "; ", all

* If plotraw option used: plot individual data points underneath the bins
* (with no by-groups the data in memory is collapsed, so raw points are appended from rawpts)
if "`plotraw'"!="" {
	if `c(stata_version)' >= 15.0 local rawopacity %50
	if ("`by'"=="") local underlying_data_scatter (scatter `raw_y' `raw_x', mc(gs11`rawopacity') msize(vsmall))
	else local underlying_data_scatter (scatter `y_vars_r' `x_r', mc(gs11`rawopacity') msize(vsmall))
}

* If line45 option used: add a dashed gray 45-degree line spanning the binned points
* (added after scatters/fits so legend numbering is unaffected)
if "`line45'"!="" {
	local lo45 = .
	local hi45 = .
	forvalues i=1/`ynum' {
		mata: st_local("m_lo", strofreal(min(st_matrix("`y`i'_scatterpts'")), "%21.0g"))
		mata: st_local("m_hi", strofreal(max(st_matrix("`y`i'_scatterpts'")), "%21.0g"))
		local lo45 = min(`lo45', `m_lo')
		local hi45 = max(`hi45', `m_hi')
	}
	if !missing(`lo45', `hi45') {
		local line45_plot (function y=x, range(`lo45' `hi45') lpattern(dash) lcolor(gs10))
	}
}

* Build graph commands (the savedata do-file omits the raw data scatter, which isn't saved)
local graphcmd twoway `underlying_data_scatter' `quantile_macro' `scatters' `fits' `line45_plot', graphregion(fcolor(white)) `xlines' xtitle(`x_var') ytitle(`ytitle') legend(`legend_labels' order(`order')) `options'
if "`savedata'"!="" local savedata_graphcmd twoway `quantile_macro' `savedata_scatters' `fits' `line45_plot', graphregion(fcolor(white)) `xlines' xtitle(`x_var') ytitle(`ytitle') legend(`savedata_legend_labels' order(`savedata_order')) `options'

* Only display graph if noplot option was not specified
if "`noplot'"=="" {
	if ("`plotraw'"!="" & "`by'"=="") qui append using "`rawpts'"
	`graphcmd'
	if ("`plotraw'"!="" & "`by'"=="") {
		qui drop if !missing(`raw_x')
		drop `raw_x' `raw_y'
	}
}

*-------------------------------------------------------------------------------
* Save results out
*-------------------------------------------------------------------------------
	
* If savegraph() specified, save the graph
if `"`savegraph'"'!="" {
	* check file extension using a regular expression
	if regexm(`"`savegraph'"',"\.[a-zA-Z0-9]+$") local graphextension=regexs(0)
	if inlist(`"`graphextension'"',".gph","") graph save `"`savegraph'"', `replace'
	else graph export `"`savegraph'"', `replace'
}

* Save data
if ("`savedata'"!="") {

	tempname savedatafile

	* With by-groups the data in memory is not collapsed: build the scatter point
	* dataset (x_var_byK, yvar_byK) from the scatter point matrices instead
	if "`by'"!="" {
		clear
		qui set obs `=rowsof(`y1_scatterpts')'
		forvalues i=1/`ynum' {
			local depvar : word `i' of `y_vars'
			forvalues k=1/`bynum' {
				if (`i'==1) qui gen double `x_var'_by`k' = `y1_scatterpts'[_n,2*`k'-1]
				qui gen double `depvar'_by`k' = `y`i'_scatterpts'[_n,2*`k']
			}
		}
	}

	* Otherwise, give temporary variables readable names: tempvar names saved to disk
	* can clash with twoway's own tempvars when the do-file is run
	else {
		foreach pair in "xq bin" "sd sd" "sd_ub sd_ub" "sd_lb sd_lb" {
			gettoken tv newname : pair
			local newname = trim("`newname'")
			if substr("``tv''",1,2)=="__" {
				cap confirm new variable `newname'
				if !_rc {
					rename ``tv'' `newname'
					local savedata_graphcmd : subinstr local savedata_graphcmd "``tv''" "`newname'", all
				}
			}
		}
	}

	* Save a dataset containing the scatter points
	if "`dataextension'"==".dta" qui save `"`savedata_file'"', `replace'
	else qui outsheet using `"`savedata_file'"', comma `replace'
	di as text `"(file `savedata_file' written containing saved data)"'

	* Save a do-file with the commands to generate a nicely labeled dataset and re-create the binscatter graph
	if "`nodofile'"=="" {
		file open `savedatafile' using `"`savedata_do'"', write text `replace'
		if "`dataextension'"==".dta" file write `savedatafile' `"use "`savedata_file'", clear"' _n _n
		else file write `savedatafile' `"insheet using "`savedata_file'", clear"' _n _n
		if "`by'"!="" {
			foreach var in `x_var' `y_vars' {
				local counter_by=0
				foreach byval in `byvals' {
					local ++counter_by
					if ("`bylabel'"=="") local byvalname=`byval'
				else {
						local byvalname `: label `bylabel' `byval''
					}
					file write `savedatafile' `"label variable `var'_by`counter_by' "`var'; `byvarname'==`byvalname'""' _n
				}
			}
			file write `savedatafile' _n
		}
		file write `savedatafile' `"`savedata_graphcmd'"' _n
		file close `savedatafile'
		di as text `"(file `savedata_do' written containing commands to process saved data)"'
	}
}

*-------------------------------------------------------------------------------
* Return items
*-------------------------------------------------------------------------------

* Restore dataset
restore

* If fast option not enabled, return stuff
if "`fast'"=="" {

	* Return sample
	ereturn post, esample(`touse')

	* Return sample size
	ereturn scalar N = `samplesize'

	* Return the graph command
	ereturn local graphcmd `"`graphcmd'"'

	* If linetype specified: return matrix of regression coefficients
	if inlist("`linetype'","lfit","qfit","expfit","logfit") {
		forvalues yi=`ynum'(-1)1 {
			ereturn matrix y`yi'_coefs=`y`yi'_coefs'
		}
	}

	* If RD option specified: return RD intervals
	if ("`rd'"!="") {
		tempname rdintervals
		matrix `rdintervals' = (. \ `=subinstr("`rd'"," ","\",.)' ) , ( `=subinstr("`rd'"," ","\",.)' \ .)
		forvalues i=1/`=rowsof(`rdintervals')' {
			local rdintervals_labels `rdintervals_labels' rd`i'
		}
		matrix rownames `rdintervals' = `rdintervals_labels'
		matrix colnames `rdintervals' = gt lt_eq
		ereturn matrix rdintervals = `rdintervals'
	}

	* If a numeric by-variable is specified: return matrix of by-values
	if ("`by'"!="" & "`by'"=="`byvarname'") {
		forvalues i=1/`=rowsof(`byvalmatrix')' {
			local byvalmatrix_labels `byvalmatrix_labels' by`i'
		}
		matrix rownames `byvalmatrix' = `byvalmatrix_labels'
		matrix colnames `byvalmatrix' = `by'
		ereturn matrix byvalues = `byvalmatrix'
	}

}

* Lastly: merge back on genxq(identifier), if applicable
if "`genxq'"!="" {
	qui merge 1:1 `temp_id' using `temp_file_2', nogen
}
	
end
