defmodule Changelog.ObanWorkers.FeedStatsProcessor do
  use Oban.Worker, queue: :scheduled, unique: [period: 600]

  alias Changelog.{Feed, FeedStat, ListKit, Podcast, Repo, UrlKit}
  alias Changelog.Stats.{S3}
  alias Ecto.Changeset

  require Logger

  @impl Oban.Worker
  def timeout(_job), do: 600_000

  @impl Oban.Worker
  def perform(%Job{args: %{"date" => date}}) do
    date = Date.from_iso8601!(date)
    logs = get_logs_grouped_by_url(date)

    for feed <- Repo.all(Feed) do
      process_feed(feed, date, logs)
    end

    for podcast <- Repo.all(Podcast) do
      process_podcast(podcast, date, logs)
    end

    :ok
  end

  defp process_feed(feed, date,logs) do
    url = "/feeds/#{feed.slug}"
    agents = get_unique_agents_map(logs, url)

    stat =
      case Repo.get_by(Ecto.assoc(feed, :feed_stats), date: date) do
        nil ->
          %FeedStat{feed_id: feed.id,date: date}
        found ->
          found
      end

    stat = Changeset.change(stat, %{agents: agents})

    case Repo.insert_or_update(stat) do
      {:ok, stat} ->
        stat
      {:error, _} ->
        Logger.info("Stats: Failed to insert/update feed: #{date} #{feed.slug}")
    end
  end

  defp process_podcast(podcast, date, logs) do
    slug = case podcast.slug do
      "backstage" -> "master"
      "interviews" -> "podcast"
      other -> other
    end

    url = "/#{slug}/feed"
    agents = get_unique_agents_map(logs, url)

    stat =
      case Repo.get_by(Ecto.assoc(podcast, :feed_stats), date: date) do
        nil ->
          %FeedStat{podcast_id: podcast.id,date: date}
        found ->
          found
      end

    stat = Changeset.change(stat, %{agents: agents})

    case Repo.insert_or_update(stat) do
      {:ok, stat} ->
        stat
      {:error, _} ->
        Logger.info("Stats: Failed to insert/update podcast: #{date} #{podcast.slug}")
    end
  end

  # returns a map where the unique agents are the keys and the values
  # are the number of requests the agent made
  defp get_unique_agents_map(logs, url) do
    logs
    |> Map.get(url, [])
    |> Enum.group_by(&Map.get(&1, "request_user_agent"))
    |> Enum.map(fn {agent, requests} -> {agent, length(requests)} end)
    |> Enum.sort_by(fn {_agent, requests} -> requests end, :desc)
    |> Enum.into(%{})
  end

  # returns one big map where the unique feed URLs are keys and the values
  # are lists of feed requests for each URL
  defp get_logs_grouped_by_url(date) do
    S3.get_logs("feeds", date)
    |> Enum.flat_map(&parse/1)
    |> Enum.map(&normalize/1)
    |> Enum.group_by(&Map.get(&1, "url"))
  end

  defp normalize(log) when is_map(log) do
    new_url = log |> Map.get("url") |> UrlKit.sans_query()
    Map.put(log, "url", new_url)
  end

  defp parse(log) when is_binary(log) do
    log
    |> String.split("\n")
    |> ListKit.compact()
    |> Enum.map(&Jason.decode!/1)
  end
end