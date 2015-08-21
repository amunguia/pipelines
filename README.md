# Pipelines

## In Development

Pipelines is inspred by running a sequence of unix commands and piping the output from one to the input of the next.  As a Haskell library, Pipelines allows you to define a sequence of functions that successively transforms a stream of input data.  Each function, called a job, runs asyncrhonously in its own thread.  Each job can be run accross an arbitrary number of threads. 

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

-- With an existing Control.Concurrent.Chan as input into the pipeline
beginWithChan :: Chan a -> IO (Pipeline a a) 
```

To append jobs to a pipeline use one of (&|) or (&|!):

```haskell
f :: a -> IO b
g :: b -> c

begin &| f &|! g :: Pipeline a c
```

It is possible to process a job in multiple threads.  In this case, each thread reads from the same input channel and writes to the same output channel. However, no guarantee is made of the outputs of job 'g' maintaining the input order.

```haskell
f :: a -> IO b
g :: b -> IO c

begin &| f &\ g `with` 3  :: Pipeline a c
```

