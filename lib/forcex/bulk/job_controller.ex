defmodule Forcex.Bulk.JobController do
  use GenServer

  def start_link(params) do
    GenServer.start_link(__MODULE__, params)
  end

  def init({:query, sobject, queries, client}) do
    send(self(), :after_init)
    {:ok, [sobject: sobject, queries: queries, client: client]}
  end

  def handle_info(:after_init, state) do
    sobject = Keyword.fetch!(state, :sobject)
    client = Keyword.fetch!(state, :client)
    {:ok, pid} = Forcex.Bulk.JobWorker.start_link({:query, sobject: sobject, client: client, handlers: [self()]})
    {:noreply, Keyword.put(state, :job_worker, pid)}
  end

  def handle_info({:job_created, job}, state) do
    client = Keyword.fetch!(state, :client)
    queries = Keyword.fetch!(state, :queries)
    for query <- queries do
      {:ok, pid} = Forcex.Bulk.BatchWorker.start_link({:query, client: client, job: job, query: query, handlers: [self()]})
    end
    IO.puts "Job #{job["id"]} created"
    {:noreply, state}
  end

  def handle_info({:batch_partial_result_ready, batch, result}, state) do
    client = Keyword.fetch!(state, :client)
    partial_results = Forcex.Bulk.fetch_results(result, batch, client)
    IO.puts("Batch #{batch["id"]} partial results: #{inspect partial_results}")

    {:noreply, state}
  end

  def handle_info({:job_status, %{"state" => "Closed"} = job}, state) do
    {:stop, :normal, Keyword.put(state, :job, job)}
  end
  def handle_info({:job_status, %{"numberBatchesCompleted" => num, "numberBatchesTotal" => num} = job}, state) do
    client = Keyword.fetch!(state, :client)
    job_worker = Keyword.fetch!(state, :job_worker)
    send(job_worker, :close_job)
    {:noreply, state}
  end
  def handle_info({:job_status, job}, state) do
    IO.puts "Job #{job["id"]} poll"
    {:noreply, state}
  end
  def handle_info({:batch_status, %{"state" => "Completed"} = batch}, state) do
    IO.puts "Batch #{batch["id"]} complete"
    {:noreply, state}
  end
  def handle_info({:batch_status, batch}, state) do
    IO.puts "Batch #{batch["id"]} poll"
    {:noreply, state}
  end
  def handle_info({:job_closed, job}, state) do
    IO.puts "Job #{job["id"]} closed"
    {:noreply, state}
  end
  def handle_info({:batch_created, batch}, state) do
    IO.puts "Batch #{batch["id"]} created"
    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.puts "Got message: #{inspect msg}"
    {:noreply, state}
  end
end
