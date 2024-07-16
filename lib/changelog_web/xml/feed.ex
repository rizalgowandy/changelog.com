defmodule ChangelogWeb.Xml.Feed do
  use ChangelogWeb, :verified_routes

  alias Changelog.{ListKit}
  alias ChangelogWeb.{EpisodeView, FeedView, PersonView, PodcastView, TimeView, Xml}
  alias ChangelogWeb.Helpers.SharedHelpers

  @doc """
  Returns a full XML document structure ready to be sent to Xml.generate/1
  """
  def document(feed, episodes) do
    {
      :rss,
      Xml.podcast_namespaces(),
      [channel(feed, episodes)]
    }
    |> XmlBuilder.document()
  end

  def channel(feed, episodes) do
    {
      :channel,
      nil,
      [
        {:title, nil, feed.name},
        {:copyright, nil, "All rights reserved"},
        {:language, nil, "en-us"},
        {:description, nil, feed.description},
        {"itunes:author", nil, "Changelog Media"},
        {"itunes:block", nil, "yes"},
        {"itunes:explicit", nil, "no"},
        {"itunes:summary", nil, feed.description},
        {"itunes:image", %{href: PodcastView.cover_url(feed)}},
        {"itunes:owner", nil, Xml.itunes_owner()},
        Enum.map(episodes, fn episode -> episode(feed, episode) end)
      ]
      |> List.flatten()
      |> ListKit.compact()
    }
  end

  def episode(feed, episode) do
    {:item, nil,
     [
       {:title, nil, FeedView.custom_episode_title(feed, episode)},
       {:guid, %{isPermaLink: false}, EpisodeView.guid(episode)},
       {:link, nil, url(~p"/#{episode.podcast.slug}/#{episode.slug}")},
       {:pubDate, nil, TimeView.rss(episode.published_at)},
       {:enclosure, enclosure(feed, episode)},
       {:description, nil, SharedHelpers.md_to_text(episode.summary)},
       {"itunes:episodeType", nil, episode.type},
       {"itunes:image", %{href: EpisodeView.cover_url(episode)}},
       {"itunes:duration", nil, duration(feed, episode)},
       {"itunes:explicit", nil, "no"},
       {"itunes:subtitle", nil, episode.subtitle},
       {"itunes:summary", nil, SharedHelpers.md_to_text(episode.summary)},
       Enum.map(episode.hosts, fn p -> Xml.person(p, "host") end),
       Enum.map(episode.guests, fn p -> Xml.person(p, "guest") end),
       Xml.transcript(episode),
       chapters(feed, episode),
       Xml.socialize(episode),
       {"content:encoded", nil, show_notes(episode)}
     ]}
  end

  defp duration(feed, episode) do
    t =
      if feed.plusplus do
        episode.plusplus_duration
      else
        episode.audio_duration
      end

    TimeView.duration(t)
  end

  defp enclosure(feed, episode) do
    {url, bytes} =
      if feed.plusplus do
        {EpisodeView.plusplus_url(episode), episode.plusplus_bytes}
      else
        {EpisodeView.audio_url(episode), episode.audio_bytes}
      end

    %{url: url, length: bytes, type: "audio/mpeg"}
  end

  defp chapters(_feed, %{audio_chapters: []}), do: nil

  defp chapters(feed, episode) do
    {chapters, url} =
      if feed.plusplus && Enum.any?(episode.plusplus_chapters) do
        {episode.plusplus_chapters,
         url(~p"/#{episode.podcast.slug}/#{episode.slug}/chapters?pp=true")}
      else
        {episode.audio_chapters, url(~p"/#{episode.podcast.slug}/#{episode.slug}/chapters")}
      end

    [
      {"podcast:chapters",
       %{
         url: url,
         type: "application/json+chapters"
       }},
      Xml.Chapters.chapters(chapters, "psc")
    ]
  end

  defp show_notes(episode) do
    sponsors = episode.episode_sponsors
    participants = EpisodeView.participants(episode)

    data =
      [
        SharedHelpers.md_to_html(episode.summary),
        FeedView.discussion_link(episode),
        ~s(<p><a href="#{url(~p"/++")}" rel="payment">Changelog++</a> #{EpisodeView.plusplus_cta(episode)} Join today!</p>),
        show_notes_sponsors(sponsors),
        show_notes_featuring(participants),
        "<p>Show Notes:</p>",
        "<p>#{SharedHelpers.md_to_html(episode.notes)}</p>",
        ~s(<p>Something missing or broken? <a href="#{EpisodeView.show_notes_source_url(episode)}">PRs welcome!</a></p>)
      ]
      |> ListKit.compact_join("")

    {:cdata, data}
  end

  defp show_notes_sponsors([]), do: nil

  defp show_notes_sponsors(sponsors) do
    items =
      Enum.map(sponsors, fn s ->
        description = s.description |> SharedHelpers.md_to_html() |> SharedHelpers.sans_p_tags()

        ~s"""
        <li><a href="#{s.link_url}">#{s.title}</a> – #{description}</li>
        """
      end)

    ["<p>Sponsors:</p><p><ul>", items, "</ul></p>"]
  end

  defp show_notes_featuring([]), do: nil

  defp show_notes_featuring(participants) do
    items =
      Enum.map(participants, fn p ->
        ~s"""
          <li>#{p.name} &ndash; #{PersonView.list_of_links(p)}</li>
        """
      end)

    ["<p>Featuring:</p><ul>", items, "</ul></p>"]
  end
end
