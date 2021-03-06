#######################################################################
#
# Package Name: SeqArray
#
# Description:
#     Big Data Management of Whole-Genome Sequence Variant Calls
#


## Package-wide variables
process_index <- 1L
process_count <- 1L

## Internal R objects
.dim_name <- list(
    geno_dim2 = list(allele=NULL, sample=NULL),
    geno_dim3 = list(allele=NULL, sample=NULL, variant=NULL),
    dosage_dim = list(sample=NULL, variant=NULL),
    data_dim  = c("length", "data"),
    data_dim2 = list(sample=NULL, variant=NULL)
)



#######################################################################

.onLoad <- function(lib, pkg)
{
    .Call(SEQ_Pkg_Init, .dim_name)
    TRUE
}

.Last.lib <- function(libpath)
{
    cl <- getOption("seqarray.parallel", FALSE)
    if (inherits(cl, "cluster"))
    {
        if (requireNamespace("parallel", quietly=TRUE))
            parallel::stopCluster(cl)
        options(seqarray.parallel=NULL)
    }
}



#######################################################################
# Get the file name of an example
#
seqExampleFileName <- function(type=c("gds", "vcf", "KG_Phase1"))
{
    type <- match.arg(type)
    switch(type,
        gds =
            system.file("extdata", "CEU_Exon.gds", package="SeqArray"),
        vcf =
            system.file("extdata", "CEU_Exon.vcf.gz", package="SeqArray"),
        KG_Phase1 =
            system.file("extdata", "1KG_phase1_release_v3_chr22.gds",
                package="SeqArray")
    )
}



#######################################################################
# Setup the parallel parameters in SeqArray
#
seqParallelSetup <- function(cluster=TRUE, verbose=TRUE)
{
    # check
    stopifnot(is.null(cluster) | is.logical(cluster) |
        is.numeric(cluster) | inherits(cluster, "cluster"))
    stopifnot(is.logical(verbose), length(verbose)==1L)

    if (is.null(cluster) || identical(cluster, FALSE))
    {
        opt <- getOption("seqarray.parallel", NULL)
        if (inherits(opt, "cluster"))
            stopCluster(opt)
        if (verbose)
            cat("Stop the computing cluster.\n")
        options(seqarray.parallel=cluster)
        return(invisible())
    }

    # Windows platform does not support forking, we have to setup a cluster
    if (.Platform$OS.type == "windows")
    {
        setup <- function(num.cores)
        {
            cl <- makeCluster(num.cores)
            clusterCall(cl, function() { library(SeqArray); NULL })
            cl
        }

        if (is.logical(cluster))
        {
            stopifnot(length(cluster) == 1L)
            if (cluster)
            {
                cl <- detectCores() - 1L
                if (cl <= 1L) cl <- 2L
                cluster <- setup(cl)
                if (verbose)
                    cat("Enable the computing cluster with", cl, "R processes.\n")
            } else {
                if (verbose) cat("No computing cluster.\n")
            }
        } else if (is.numeric(cluster))
        {
            stopifnot(length(cluster) == 1L)
            if (cluster > 1L)
            {
                cl <- cluster
                cluster <- setup(cluster)
                if (verbose)
                    cat("Enable the computing cluster with", cl, "R processes.\n")
            }
        }
    } else {
        # unix forking technique
        if (identical(cluster, TRUE))
        {
            n <- detectCores() - 1L
            if (n <= 1L) n <- 2L
            if (verbose)
                cat("Enable the computing cluster with", n, "forked R processes.\n")
        } else if (is.numeric(cluster))
        {
            stopifnot(length(cluster) == 1L)
            if (cluster > 1L)
            {
                if (verbose)
                    cat("Enable the computing cluster with", cluster, "forked R processes.\n")
            }
        }
    }

    options(seqarray.parallel=cluster)
    invisible()
}



#######################################################################
# Get the parallel parameters in SeqArray
#
seqGetParallel <- function()
{
    getOption("seqarray.parallel", FALSE)
}



#######################################################################
# Storage options for the SeqArray GDS file
#
seqStorageOption <- function(compression=c("ZIP_RA", "ZIP_RA.fast",
    "ZIP_RA.max", "LZ4_RA", "LZ4_RA.fast", "LZ4_RA.max",
    "LZMA_RA", "LZMA_RA.fast", "LZMA_RA.max", "none"), mode=NULL,
    float.mode="float32", geno.compress=NULL, info.compress=NULL,
    format.compress=NULL, index.compress=NULL, ...)
{
    # check
    compression <- match.arg(compression)
    if (compression == "none") compression <- ""

    stopifnot(is.null(mode) | is.character(mode))
    stopifnot(is.character(float.mode), length(float.mode) > 0L)

    if (!is.null(geno.compress))
        stopifnot(is.character(geno.compress), length(geno.compress)==1L)
    if (!is.null(info.compress))
        stopifnot(is.character(info.compress), length(info.compress)==1L)
    if (!is.null(format.compress))
        stopifnot(is.character(format.compress), length(format.compress)==1L)
    if (!is.null(index.compress))
        stopifnot(is.character(index.compress), length(index.compress)==1L)

    if (compression %in% c("ZIP_RA.max", "LZ4_RA.max", "LZMA_RA.max"))
        suffix <- ":8M"
    else
        suffix <- ":1M"

    rv <- list(compression = compression,
        mode = mode, float.mode = float.mode,
        geno.compress = ifelse(is.null(geno.compress), compression,
            geno.compress),
        info.compress = ifelse(is.null(info.compress), compression,
            info.compress),
        format.compress = ifelse(is.null(format.compress),
            ifelse(compression=="", "", paste0(compression, suffix)),
            format.compress),
        index.compress = ifelse(is.null(index.compress), compression,
            index.compress),
        ...)
    class(rv) <- "SeqGDSStorageClass"
    return(rv)
}



#######################################################################
# Apply functions in parallel
#
seqParallel <- function(cl=seqGetParallel(), gdsfile, FUN,
    split=c("by.variant", "by.sample", "none"), .combine="unlist",
    .selection.flag=FALSE, ...)
{
    # check
    stopifnot(is.null(cl) | is.logical(cl) | is.numeric(cl) |
        inherits(cl, "cluster") | inherits(cl, "BiocParallelParam"))
    stopifnot(is.null(gdsfile) | inherits(gdsfile, "SeqVarGDSClass"))
    stopifnot(is.function(FUN))
    split <- match.arg(split)
    stopifnot(is.character(.combine) | is.function(.combine))
    stopifnot(is.logical(.selection.flag))

    if (is.character(.combine))
    {
        stopifnot(length(.combine) == 1L)
        if (!(.combine %in% c("unlist", "list", "none")))
            .combine <- match.fun(.combine)
    }

    if (is.null(gdsfile))
    {
        if (split != "none")
            stop("'split' should be 'none' if 'gdsfile=NULL'.")
    }

    njobs <- .NumParallel(cl)
    if (njobs <= 1L)
    {
        ## a single process
        .Call(SEQ_IntAssign, process_index, 1L)
        .Call(SEQ_IntAssign, process_count, 1L)

        if (.selection.flag)
        {
            dm <- .seldim(gdsfile)
            if (split == "by.variant")
                ans <- FUN(gdsfile, rep(TRUE, dm[3L]), ...)
            else if (split == "by.sample")
                ans <- FUN(gdsfile, rep(TRUE, dm[2L]), ...)
            else
                ans <- FUN(gdsfile, NULL, ...)
        } else {
            if (is.null(gdsfile))
                ans <- FUN(...)
            else
                ans <- FUN(gdsfile, ...)
        }

    } else if (inherits(cl, "cluster"))
    {
        ## multiple processes with a predefined cluster

        if (split %in% c("by.variant", "by.sample"))
        {
            dm <- .seldim(gdsfile)
            if (split == "by.variant")
            {
                if (dm[3L] <= 0) stop("No variants selected.")
                if (length(cl) > dm[3L]) cl <- cl[seq_len(dm[3L])]
            } else {
                if (dm[2L] <= 0) stop("No samples selected.")
                if (length(cl) > dm[2L]) cl <- cl[seq_len(dm[2L])]
            }

            sel <- seqGetFilter(gdsfile, .useraw=TRUE)
        } else {
            sel <- list(sample.sel=raw(), variant.sel=raw())
        }

        ans <- .DynamicClusterCall(cl, length(cl), .fun =
            function(.proc_idx, .proc_cnt, .gds.fn, .sel_sample, .sel_variant,
                FUN, .split, .selection.flag, ...)
        {
            # export to global variables
            .Call(SEQ_IntAssign, process_index, .proc_idx)
            .Call(SEQ_IntAssign, process_count, .proc_cnt)

            # load the package
            library("SeqArray")

            if (is.null(.gds.fn))
            {
                # call the user-defined function
                FUN(...)
            } else {
                # open the file
                .file <- seqOpen(.gds.fn, readonly=TRUE, allow.duplicate=TRUE)
                on.exit({ seqClose(.file) })

                # set filter
                seqSetFilter(.file,
                    sample.sel = memDecompress(.sel_sample, type="gzip"),
                    variant.sel = memDecompress(.sel_variant, type="gzip"),
                    verbose=FALSE)
                .ss <- .Call(SEQ_SplitSelection, .file, .split, .proc_idx,
                    .proc_cnt, .selection.flag)

                # call the user-defined function
                if (.selection.flag)
                    FUN(.file, .ss, ...)
                else
                    FUN(.file, ...)
            }

        }, .combinefun = .combine, .stopcluster=FALSE,
            .proc_cnt = njobs, .gds.fn = gdsfile$filename,
            .sel_sample = memCompress(sel$sample.sel, type="gzip"),
            .sel_variant = memCompress(sel$variant.sel, type="gzip"),
            FUN = FUN, .split = split, .selection.flag=.selection.flag,
            ...
        )

        if (is.list(ans) & identical(.combine, "unlist"))
            ans <- unlist(ans, recursive=FALSE)

    } else if (inherits(cl, "BiocParallelParam"))
    {
        ## multiple processes with a predefined cluster from BiocParallel

        if (split %in% c("by.variant", "by.sample"))
        {
            dm <- .seldim(gdsfile)
            if (split == "by.variant")
            {
                if (dm[3L] <= 0) stop("No variants selected.")
            } else {
                if (dm[2L] <= 0) stop("No samples selected.")
            }

            sel <- seqGetFilter(gdsfile, .useraw=TRUE)
        } else {
            sel <- list(sample.sel=raw(), variant.sel=raw())
        }

        ans <- BiocParallel::bplapply(seq_len(njobs), FUN =
            function(.proc_idx, .proc_cnt, .gds.fn, .sel_sample, .sel_variant,
                .FUN, .split, .selection.flag, ...)
        {
            # export to global variables
            .Call(SEQ_IntAssign, process_index, .proc_idx)
            .Call(SEQ_IntAssign, process_count, .proc_cnt)

            # load the package
            library("SeqArray")

            if (is.null(.gds.fn))
            {
                # call the user-defined function
                .FUN(...)
            } else {
                # open the file
                .file <- seqOpen(.gds.fn, readonly=TRUE, allow.duplicate=TRUE)
                on.exit({ seqClose(.file) })

                # set filter
                seqSetFilter(.file,
                    sample.sel = memDecompress(.sel_sample, type="gzip"),
                    variant.sel = memDecompress(.sel_variant, type="gzip"),
                    verbose=FALSE)
                .ss <- .Call(SEQ_SplitSelection, .file, .split, .proc_idx,
                    .proc_cnt, .selection.flag)

                # call the user-defined function
                if (.selection.flag)
                    .FUN(.file, .ss, ...)
                else
                    .FUN(.file, ...)
            }

        },  .proc_cnt = njobs, .gds.fn = gdsfile$filename,
            .sel_sample = memCompress(sel$sample.sel, type="gzip"),
            .sel_variant = memCompress(sel$variant.sel, type="gzip"),
            .FUN = FUN, .split = split, .selection.flag=.selection.flag,
            ..., BPPARAM=cl)

        if (is.list(ans))
        {
            if (identical(.combine, "unlist"))
            {
                ans <- unlist(ans, recursive=FALSE)
            } else if (is.function(.combine))
            {
                rv <- ans[[1L]]
                for (i in seq_len(length(ans)-1L) + 1L)
                    rv <- .combine(rv, ans[[i]])
                ans <- rv
            }
        }

    } else {

        ## multiple processes with a predefined number of cores

        if (.Platform$OS.type == "windows")
        {
            # no forking on windows
            cl <- makeCluster(njobs)
            on.exit({ stopCluster(cl) })

            return(seqParallel(cl, gdsfile, FUN, split, .combine,
                .selection.flag, ...))
        }

        if (split %in% c("by.variant", "by.sample"))
        {
            dm <- .seldim(gdsfile)
            if (split == "by.variant")
            {
                if (dm[3L] <= 0) stop("No variants selected.")
                if (cl > dm[2L]) cl <- dm[2L]
            } else {
                if (dm[2L] <= 0) stop("No samples selected.")
                if (cl > dm[1L]) cl <- dm[1L]
            }
        } else {
            sel <- list(sample.sel=raw(), variant.sel=raw())
        }

        ans <- mclapply(seq_len(njobs),
            mc.preschedule=FALSE, mc.cores=njobs, mc.cleanup=TRUE,
            FUN = function(i, .fun)
            {
                # export to global variables
                .Call(SEQ_IntAssign, process_index, i)
                .Call(SEQ_IntAssign, process_count, cl)

                if (is.null(gdsfile))
                {
                    # call the user-defined function
                    FUN(...)
                } else {
                    sel <- .Call(SEQ_SplitSelection, gdsfile, split, i, cl,
                        .selection.flag)

                    # call the user-defined function
                    if (.selection.flag)
                        FUN(gdsfile, sel, ...)
                    else
                        FUN(gdsfile, ...)
                }
            }, .fun = FUN)

        if (is.list(ans))
        {
            if (identical(.combine, "unlist"))
            {
                ans <- unlist(ans, recursive=FALSE)
            } else if (is.function(.combine))
            {
                rv <- ans[[1L]]
                for (i in seq_len(length(ans)-1L) + 1L)
                    rv <- .combine(rv, ans[[i]])
                ans <- rv
            }
        }
    }

    # output
    if (identical(.combine, "none"))
        invisible()
    else
        ans
}


seqParApply <- function(cl=seqGetParallel(), x, FUN, load.balancing=TRUE, ...)
{
    njobs <- .NumParallel(cl, "cl")
    stopifnot(is.logical(load.balancing))

    if (njobs <= 1L)
    {
        ## a single process
        ans <- lapply(x, FUN, ...)
    } else if (inherits(cl, "BiocParallelParam"))
    {
        ans <- BiocParallel::bplapply(x, FUN, ..., BPPARAM=cl)
    } else {
        if (!inherits(cl, "cluster"))
        {
            if (.Platform$OS.type == "windows")
                cl <- makeCluster(njobs)
            else
                cl <- makeForkCluster(njobs)
            on.exit({ stopCluster(cl) })
        }

        # a load balancing version
        if (isTRUE(load.balancing))
            ans <- clusterApplyLB(cl, x, FUN, ...)
        else
            ans <- clusterApply(cl, x, FUN, ...)
    }

    ans
}



#######################################################################
# Modify the SeqArray data structure
#######################################################################

#######################################################################
# Delete data variables
#

seqDelete <- function(gdsfile, info.varname=character(),
    format.varname=character(), samp.varname=character(), verbose=TRUE)
{
    # check
    stopifnot(inherits(gdsfile, "SeqVarGDSClass"))
    if (gdsfile$readonly)
        stop("The GDS file is read-only.")

    stopifnot(is.character(info.varname))
    stopifnot(is.character(format.varname))
    stopifnot(is.character(samp.varname))
    stopifnot(is.logical(verbose), length(verbose)==1L)

    if (verbose) cat("Delete INFO variable(s):")
    for (nm in info.varname)
    {
        n <- index.gdsn(gdsfile, paste0("annotation/info/", nm))
        delete.gdsn(n, force=TRUE)
        n <- index.gdsn(gdsfile, paste0("annotation/info/@", nm), silent=TRUE)
        if (!is.null(n))
            delete.gdsn(n, force=TRUE)
        if (verbose) cat("", nm)
    }
    if (verbose) cat("\n")

    if (verbose) cat("Delete FORMAT variable(s):")
    for (nm in format.varname)
    {
        n <- index.gdsn(gdsfile, paste0("annotation/format/", nm))
        delete.gdsn(n, force=TRUE)
        if (verbose) cat("", nm)
    }
    if (verbose) cat("\n")

    if (verbose) cat("Delete Sample Annotation variable(s):")
    for (nm in samp.varname)
    {
        n <- index.gdsn(gdsfile, paste0("sample.annotation/", nm))
        delete.gdsn(n, force=TRUE)
        if (verbose) cat("", nm)
    }
    if (verbose) cat("\n")

    # return
    invisible()
}



#######################################################################
# Transpose data variable(s)
#

.Transpose <- function(gdsfile, src.fn, prefix, compress=NULL)
{
    dst.fn <- .var_path(src.fn, prefix)
    if (is.null(index.gdsn(gdsfile, dst.fn, silent=TRUE)))
    {
        node <- index.gdsn(gdsfile, src.fn)
        desp <- objdesp.gdsn(node)
        dm <- desp$dim
        if (length(dm) > 1L)
        {
            # dimension
            dm <- c(dm[-(length(dm)-1L)], 0L)
            # folder
            nm <- unlist(strsplit(src.fn, "/"))
            if (length(nm) <= 1)
                folder <- gdsfile$root
            else
                folder <- index.gdsn(gdsfile, index=nm[-length(nm)])
            # compress
            if (is.null(compress))
                compress <- desp$compress

            pm <- list(node = folder,
                name = paste(prefix, nm[length(nm)], sep=""),
                val = NULL, storage = desp$storage,
                valdim = dm, compress = compress)
            if (!is.null(desp$param))
                pm <- c(pm, desp$param)

            newnode <- do.call(add.gdsn, pm)
            moveto.gdsn(newnode, node, relpos="after")

            # write data
            apply.gdsn(node, margin=length(dm)-1L, as.is="gdsnode",
                FUN=`c`, target.node=newnode, .useraw=TRUE)

            readmode.gdsn(newnode)
        }
    }
    invisible()
}


seqTranspose <- function(gdsfile, var.name, compress=NULL, verbose=TRUE)
{
    # check
    stopifnot(inherits(gdsfile, "SeqVarGDSClass"))
    stopifnot(is.character(var.name) & is.vector(var.name))
    stopifnot(length(var.name) == 1L)

    node <- index.gdsn(gdsfile, var.name)
    desp <- objdesp.gdsn(node)
    dm <- desp$dim
    if (length(dm) > 1L)
    {
        # dimension
        dm <- c(dm[-(length(dm)-1L)], 0L)
        # folder
        index <- unlist(strsplit(var.name, "/"))
        if (length(index) <= 1L)
            folder <- gdsfile$root
        else
            folder <- index.gdsn(gdsfile, index=index[-length(index)])
        # compress
        if (is.null(compress))
            compress <- desp$compress

        name <- paste("~", index[length(index)], sep="")
        newnode <- add.gdsn(folder, name, val=NULL, storage=desp$storage,
            valdim=dm, compress=compress)

        # write data
        apply.gdsn(node, margin=length(dm)-1L, as.is="none", FUN=function(g) {
            append.gdsn(newnode, g)
        }, .useraw=TRUE)

        readmode.gdsn(newnode)
    } else
        warning("It is a vector.")

    invisible()
}



#######################################################################
# Optimize data by transposing
#

seqOptimize <- function(gdsfn, target=c("by.sample"),
    format.var=TRUE, cleanup=TRUE, verbose=TRUE)
{
    # check
    stopifnot(is.character(gdsfn) & is.vector(gdsfn))
    target <- match.arg(target)
    stopifnot(is.logical(format.var) || is.character(format.var))
    stopifnot(is.logical(cleanup))
    stopifnot(is.logical(verbose))

    gdsfile <- seqOpen(gdsfn, readonly=FALSE)
    on.exit({ seqClose(gdsfile) })

    if (target == "by.sample")
    {
        # genotype
        if (verbose) cat("Working on 'genotype' ...\n")
        .Transpose(gdsfile, "genotype/data", "~")

        # phase
        if (verbose) cat("Working on 'phase' ...\n")
        .Transpose(gdsfile, "phase/data", "~")

        # annotation - format
        if (identical(format.var, TRUE) || is.character(format.var))
        {
            n <- index.gdsn(gdsfile, "annotation/format", silent=TRUE)
            if (!is.null(n))
            {
                nm <- ls.gdsn(n)
                if (identical(format.var, TRUE))
                    format.var <- nm
                for (i in nm)
                {
                    if (i %in% format.var)
                    {
                        if (verbose)
                        {
                            cat("Working on 'annotation/format/", i,
                                "' ...\n", sep="")
                        }
                        .Transpose(gdsfile,
                            paste("annotation/format", i, "data", sep="/"), "~")
                    }
                }
            }
        }
    }

    if (cleanup)
    {
        on.exit()
        seqClose(gdsfile)
        cleanup.gds(gdsfn, verbose=verbose)
    }

    invisible()
}
