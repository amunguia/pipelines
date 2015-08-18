# Pipelines

Pipelines is inspred by running a sequence of unix commands and piping the output from one to the input of the next.  As a Haskell library, Pipelines allows you to define a sequence of functions that successively transforms a stream of input data.  Each function, called a job, runs asyncrhonously in its own thread.  Each job can be run accross an arbitrary number of threads.  Exception handling is available at the pipeline level or at the level of a specific job. 

## Getting Started

To use in a project use

```
cabal install pipelines
```

and then 
```haskell
import Control.Concurrent.Pipelines
```

Pipelines exposes a Pipeline data type

```haskell
Pipeline a b
```
where 'a' is the type of data that is the input into the pipeline and 'b' is the type of data emitted by the pipeline. 

To create a pipeline use one of:

```haskell
begin :: IO (Pipeline a a)

-- With an existing Control.Concurrent.Chan
beginWithChan :: Chan a -> IO (Pipeline a a) 
```

To append jobs to a pipeline use one of (&|) or (&|!):

```haskell
f :: a -> IO b
g :: b -> c

begin &| f &|! g :: Pipeline a c
```

If a job 'g' is more computationally expensive than a job 'f', multiple threads
can be started to execute the expensive job.  In this case, each thread reads from the same input channel and writes to the same output channel with multiple threads processing the same stage.

```haskell
f :: a -> IO b
g :: b -> IO c

begin &| f &\ g `with` 3  :: Pipeline a c
```