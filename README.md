
binscatter3
=================================

A personal fork of [binscatter2](https://github.com/mdroste/stata-binscatter2) (v0.91, Michael Droste) that adds a `line45` option.

`binscatter3` is identical to `binscatter2` except for:

- **`line45`**: overlays a dashed gray 45-degree (y = x) reference line spanning the smallest to largest binned point (across both axes, all y-variables, and all `by()` groups). It's drawn after the scatters and fit lines, so legend numbering is unchanged, and it's included in the do-file written by `savedata()`.
- The command, help file, and package are renamed `binscatter3` so it can be installed alongside `binscatter2`.

```stata
ssc install gtools
net install binscatter3, from("https://raw.githubusercontent.com/njjenkins/stata-binscatter3/master/") replace

sysuse nlsw88, clear
regress wage tenure age grade
predict wage_hat
binscatter3 wage wage_hat, line45 line(none)
```

Everything below is the original binscatter2 README; references to `binscatter2` apply equally to `binscatter3`. The benchmark do-files in `benchmarks/` are from upstream and still call `binscatter2`.

---

Overview
---------------------------------

binscatter2 is a program for producing binned scatterplots in Stata. It inherits the syntax and functionality of the excellent [binscatter](https://github.com/michaelstepner/binscatter) package, but runs substantially faster for big datasets (see [benchmarks](#benchmarks)). In practice, binscatter2 runs approximately 3 to 4 times faster than binscatter, and 2 to 3 times faster than binsreg.

In addition, binscatter2 offers a handful of new features relative to the binscatter. Binscatter2 allows users to plot additional information about the conditional probability distribution of y given x (e.g. quantile intervals), an alternative procedure to adjust for covariates suggested by [Cattaneo et al. (2022)](https://nppackages.github.io/references/Cattaneo-Crump-Farrell-Feng_2022_Binscatter.pdf), additional options for fit lines and saving, and multi-way fixed effects.



New Features
---------------------------------

In addition to substantial performance improvements for large datasets (see [benchmarks](#benchmarks)), binscatter2 adds a few new features to binscatter. In particular:

- [x] **Multi-way fixed effects**. If [reghdfe](https://github.com/sergiocorreia/reghdfe) is installed, multi-way fixed effects can be specified in the absorb() option.
- [x] **Visualize conditional variance and quantiles**. Overlay quantiles of the sample distribution on top of the means/medians within each bin, providing more information on the shape of the conditional distribution of y given x.
- [x] **Flexible save commands**. Save scatter points out to .dta files and also choose to omit the do-file created by savedata() with the nodofile option.
- [x] **More fit line options**. Exponential and logarithmic fits, with higher-order polynomials coming soon.
- [x] **Alternative covariate adjustment procedure**. Implements the suggested procedure described in [Cattaneo et al. (2019)](https://sites.google.com/site/nppackages/binsreg/Cattaneo-Crump-Farrell-Feng_2019_Binscatter.pdf) to control for covariates without residualizing y and x with respect to a vector of controls/fixed effects with the new option altcontrols. 

![binscatter2 demo](benchmarks/ex.png "binscatter2 demo")


Installation
---------------------------------

There are two options for installing binscatter2. The only prerequisite is the gtools command, which can be installed from Github or the SSC repository.


1. The most recent version can be installed from Github with the following Stata command:

```stata
ssc install gtools
net install binscatter3, from("https://raw.githubusercontent.com/njjenkins/stata-binscatter3/master/")
```

2. A ZIP containing the program can be downloaded and manually placed on the user's adopath from Github.

This project will be submitted to the SSC repository very soon.


Usage
---------------------------------

Complete internal documentation is provided with the installation and can be accessed by typing:
```stata
help binscatter3
````

The basic syntax and usage of binscatter2 is inherited from binscatter and should be familiar to existing users of that program.

This repository includes a do-file, check.do, that provides a number of checks to verify the functionality of each option within binscatter2 and demonstrates equivalence to binscatter for options shared by both programs. The file check_speed.do runs Monte Carlo simulations that were used in the benchmark section of this readme.



Benchmarks
---------------------------------

![binscatter2 benchmark](benchmarks/benchmarks.png "binscatter2 benchmark")


  
Todo
---------------------------------

The following items will be addressed soon:

- [ ] Save out quantile intervals when using savedata() option
- [ ] More aesthetic options on quantiles() option
- [ ] Comparison against binsreg


Acknowledgements
---------------------------------

Binscatter2 builds extensively on [binscatter](https://github.com/michaelstepner/binscatter) , developed by the illustrious [Michael Stepner](https://github.com/michaelstepner) and Jessica Laird. 

In addition, binscatter2 would certainly not have been possible without [gtools](https://github.com/mcaceresb/stata-gtools) by Mauricio Caceres Bravo, which in turn would not have happened without [ftools](https://github.com/sergiocorreia/ftools), developed by Sergio Correa.

The alternative covariate adjustment procedure (enabled with the option altcontrols) was formalized by [Cattaneo et al. (2022)](https://nppackages.github.io/references/Cattaneo-Crump-Farrell-Feng_2022_Binscatter.pdf).


License
---------------------------------

binscatter2 is [MIT-licensed](https://github.com/mdroste/stata-binscatter2/blob/master/LICENSE).
