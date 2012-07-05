class Service::GithubIssues < Service
  string :access_token, :label_prefix, :milestone_prefix, :assignee_prefix,
         :update_labels_when_opened, :update_labels_when_closed,
         :update_labels_when_reopened, :update_labels_when_commented,
         :removal_prefix, :substitutions

  TOKEN_REGEX = /\"[^\"]+\"|[-\d\w]+/
  USER_REGEX  = /[-\d\w]+/

  self.title = 'Github:issues'

  def receive_issue_comment    
    if issue.closed_at == issue.updated_at
      # Avoid race condition when "Close & comment" is clicked by waiting and
      # then reloading the issue labels.
      sleep 5
      reload_issue_labels
    end

    update_issue!(:milestone => message_milestone(comment_body))
    update_issue!(:assignee  => message_assignee(comment_body))
    update_labels!(action_labels(:commented) + message_labels(comment_body))
  end

  def receive_issues
    labels = []

    if payload['action'] == 'opened'
      update_issue!(:milestone => message_milestone(issue_body))
      update_issue!(:assignee  => message_assignee(issue_body))
      labels = message_labels(issue_body)
    end

    update_labels!(action_labels + labels)
  end

  def action_labels(action = payload['action'])
    if update_labels = data["update_labels_when_#{action}"]
      update_labels.split(/,\s*/)
    else
      []
    end
  end

  def comment_body
    @body ||= substitute(comment.body)
  end

  def issue_body
    @body ||= substitute(issue.body)
  end

  def substitute(body)
    subs = data['substitutions']
    subs = (JSON.parse(subs) rescue {}) if subs.kind_of?(String)
    subs.each do |string, replacement|
      body = body.gsub(string, replacement)
    end if subs
    body
  end

  def message_labels(body)
    if prefix = data['label_prefix']
      body = scrub_prefixes(body, ['milestone_prefix', 'assignee_prefix'])
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

  def message_milestone(body)
    if prefix = data['milestone_prefix']
      title = body.scan(/#{prefix}(#{TOKEN_REGEX})/).map(&:first).last
      milestone_number(title)
    end
  end

  def message_assignee(body)
    if prefix = data['assignee_prefix']
      body.scan(/#{prefix}@(#{USER_REGEX})/).map(&:first).last
    end
  end

  def issue_labels
    @issue_labels ||= issue.labels.map {|l| l['name']}.to_set
  end

  def reload_issue_labels
    @issue_labels = get_json(issue_url)['labels'].map {|l| l['name']}.to_set
  end

  def update_labels!(labels)
    if labels.any?
      old_labels = issue_labels
      new_labels = old_labels.dup

      removal_prefix = data['removal_prefix']

      labels.each do |label|
        if removal_prefix and label =~ /#{removal_prefix}(#{TOKEN_REGEX})/
          new_labels.delete($1)
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

    response = http_method(:patch, issue_url, attrs.to_json)
    JSON.parse(response.body)
  end

  def milestone_number(title)
    return unless title

    [:open, :closed].each do |state|
      get_json(milestones_url(state)).each do |milestone|
        return milestone['number'] if milestone['title'] == title
      end
    end
    nil
  end

  def get_json(url)
    response = http_get(url)
    JSON.parse(response.body)
  end

  def token
    @token ||= data['access_token']
  end

  def repo_url
    @repo_url ||= payload['repository']['url']
  end

  def issue_url
    @issue_url ||= begin
      issue_num = payload['issue']['number']
      "#{repo_url}/issues/#{issue_num}?access_token=#{token}"
    end
  end

  def milestones_url(state)
    "#{repo_url}/milestones?state=#{state}&access_token=#{token}"
  end
end
