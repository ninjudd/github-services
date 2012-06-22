class Service::GithubIssues < Service
  string :access_token, :label_prefix, :milestone_prefix, :assignee_prefix,
         :update_labels_when_opened, :update_labels_when_closed,
         :update_labels_when_reopened, :update_labels_when_commented

  TOKEN_REGEX = /\"[^\"]+\"|[-\d\w]+/
  USER_REGEX  = /[-\d\w]+/

  self.title = 'Github:issues'

  def repo_url
    @repo_url ||= payload['repository']['url']
  end

  def url
    @url ||= begin
      issue_num = payload['issue']['number']
      token     = data['access_token']
      "#{repo_url}/issues/#{issue_num}?access_token=#{token}"
    end
  end

  def receive_issue_comment
    update_labels!(action_labels(:commented) + comment_labels)
    update_issue!(:milestone => comment_milestone, :assignee => comment_assignee)
  end

  def receive_issues
    update_labels!(action_labels)
  end

  def action_labels(action = payload['action'])
    if update_labels = data["update_labels_when_#{action}"]
      update_labels.split(/,\s*/)
    else
      []
    end
  end

  def comment_labels
    if prefix = data['label_prefix']
      body = scrub_prefixes(comment.body, ['milestone_prefix', 'assignee_prefix'])
      body.scan(/#{prefix}(#{TOKEN_REGEX})/).map(&:first)
    else
      []
    end
  end

  def scrub_prefixes(body, prefixes)
    prefixes.each do |prefix|
      body = body.gsub(data[prefix], '') if data[prefix]
    end
    body
  end

  def comment_milestone
    if prefix = data['milestone_prefix']
      title = comment.body.scan(/#{prefix}(#{TOKEN_REGEX})/).map(&:first).last
      milestone_number(title)
    end
  end

  def comment_assignee
    if prefix = data['assign_prefix']
      comment.body.scan(/#{prefix}@(#{USER_REGEX})/).map(&:first).last
    end
  end

  def update_labels!(labels)
    if labels.any?
      old_labels = issue.labels.map {|l| l['name']}.to_set
      new_labels = old_labels.dup

      labels.each do |label|
        if label.start_with?('-')
          new_labels.delete(label[1..-1])
        else
          new_labels << label
        end
      end

      if old_labels != new_labels
        set_labels!(new_labels)
      end
    end
  end

  def set_labels!(labels)
    body = update_issue!(:labels => labels)

    if missing = (body['errors'] || []).detect {|e| e['code'] == 'missing'}
      set_labels!(labels - missing['value'])
    end
  end

  def update_issue!(attrs)
    attrs = attrs.delete_if {|k,v| v.nil?}
    return if attrs.empty?

    response = http_method(:patch, url, attrs.to_json)
    JSON.parse(response.body)
  end

  def milestone_number(title)
    return unless title

    [:open, :closed].each do |state|
      get_json("#{repo_url}/milestones?state=#{state}").each do |milestone|
        return milestone['number'] if milestone['title'] == title
      end
    end
  end

  def get_json(url)
    response = http_get(url)
    JSON.parse(response.body)
  end
end
