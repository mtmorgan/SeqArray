\name{seqOpen}
\alias{seqOpen}
\title{Open a SeqArray GDS File}
\description{
    Opens a SeqArray GDS file.
}
\usage{
seqOpen(gds.fn, readonly=TRUE, allow.duplicate=FALSE)
}
\arguments{
    \item{gds.fn}{the file name}
    \item{readonly}{whether read-only or not}
    \item{allow.duplicate}{if \code{TRUE}, it is allowed to open a GDS file
        with read-only mode when it has been opened in the same R session}
}
\value{
    Return an object of class \code{\link[gdsfmt]{gds.class}}.
}
\details{
    It is strongly suggested to call \code{seqOpen} instead of
\code{\link{openfn.gds}}, since \code{seqOpen} will perform internal checking
for data integrality.
}

\author{Xiuwen Zheng}
\seealso{
    \code{\link{seqClose}}, \code{\link{seqGetData}},
    \code{\link{seqApply}}
}

\examples{
# the GDS file
(gds.fn <- seqExampleFileName("gds"))

# open the GDS file
gdsfile <- seqOpen(gds.fn)

# display the contents of the GDS file in a hierarchical structure
gdsfile

# close the GDS file
seqClose(gdsfile)
}

\keyword{gds}
\keyword{sequencing}
\keyword{genetics}
