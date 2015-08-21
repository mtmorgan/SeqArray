\name{seqParallelSetup}
\alias{seqParallelSetup}
\title{Setup a Parallel Environment}
\description{
    Setups a parallel environment in R.
}
\usage{
seqParallelSetup(cluster=TRUE)
}
\arguments{
    \item{cluster}{\code{NULL} or \code{FALSE}: serial processing; \code{TRUE}:
        parallel processing with the maximum number of cores minor one;
        a numeric value: the number of cores to be used;
        a cluster object for parallel processing, created by the functions
        in the package \code{\link{parallel}}, like \code{\link{makeCluster}}.
        See details}
}
\details{
    When \code{cl} is \code{TRUE} or a numeric value, forking techniques are
used to create a new child process as a copy of the current R process, see
\code{?parallel::mcfork}. However, forking is not available on Windows, so
multiple processes created by \code{\link{makeCluster}} are used instead.
    The R environment option \code{seqarray.parallel} will be set according
to the value of \code{cluster}.
}
\value{
    None.
}

\author{Xiuwen Zheng}
\seealso{
    \code{\link{seqParallel}}, \code{\link{seqApply}}
}

\examples{
library(parallel)

seqParallelSetup(2L)

# the GDS file
(gds.fn <- seqExampleFileName("gds"))

# display
(f <- seqOpen(gds.fn))

# run in parallel
summary(seqMissing(f))

# close the GDS file
seqClose(f)

seqParallelSetup(FALSE)
}

\keyword{gds}
\keyword{sequencing}
\keyword{genetics}