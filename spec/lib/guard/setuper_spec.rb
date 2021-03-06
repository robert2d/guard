require "guard/plugin"

require "guard/setuper"

RSpec.describe Guard::Setuper do

  let(:evaluator) { instance_double(Guard::Guardfile::Evaluator) }
  let(:pry_interactor) { double(Guard::Jobs::PryWrapper) }
  let(:sleep_interactor) { double(Guard::Jobs::Sleep) }
  let(:guardfile) { File.expand_path("Guardfile") }

  before do
    Guard::Interactor.enabled = true
    allow(Dir).to receive(:chdir)
    allow(Guard::Jobs::PryWrapper).to receive(:new).and_return(pry_interactor)
    allow(Guard::Jobs::Sleep).to receive(:new).and_return(sleep_interactor)
  end

  # TODO: setup has too many responsibilities
  describe ".setup" do
    subject { Guard.setup(options) }

    let(:options) { { my_opts: true, guardfile: guardfile } }

    let(:listener) { instance_double(Listen::Listener) }

    before do
      allow(Listen).to receive(:to).with(Dir.pwd, {}) { listener }
      allow(Guard::Notifier).to receive(:turn_on)

      stub_guardfile(" ")
      stub_user_guard_rb
    end

    it "returns itself for chaining" do
      expect(subject).to be Guard
    end

    it "initializes the plugins" do
      expect(subject.plugins.map(&:name)).to eq ["reevaluator"]
    end

    it "initializes the groups" do
      expect(subject.groups.map(&:name)).to eq [:common, :default]
      expect(subject.groups.map(&:options)).to eq [{}, {}]
    end

    it "lazily initializes the options" do
      expect(subject.options[:my_opts]).to be_truthy
    end

    it "lazily initializes the evaluator" do
      expect(subject.evaluator).to be_kind_of(Guard::Guardfile::Evaluator)
    end

    it "initializes the listener" do
      expect(subject.listener).to be(listener)
    end

    it "respect the watchdir option" do
      if Gem.win_platform?
        expect(Listen).to receive(:to).
          with("C:/usr", {}) { listener }
      else
        expect(Listen).to receive(:to).
          with("/usr", {}) { listener }
      end

      Guard.setup(watchdir: "/usr")
    end

    it "respect the watchdir option with multiple directories" do
      if Gem.win_platform?
        expect(Listen).to receive(:to).
          with("C:/usr", "C:/bin", {}) { listener }
      else
        expect(Listen).to receive(:to).
          with("/usr", "/bin", {}) { listener }
      end

      ::Guard.setup(watchdir: ["/usr", "/bin"])
    end

    it "call setup_signal_traps" do
      expect(Guard).to receive(:_setup_signal_traps)

      subject
    end

    it "evaluates the Guardfile" do
      expect(Guard).to receive(:evaluate_guardfile)

      subject
    end

    it "displays an error message when no guard are defined in Guardfile" do
      expect(Guard::UI).to receive(:error).
        with("No plugins found in Guardfile, please add at least one.")

      subject
    end

    it "call setup_notifier" do
      expect(Guard).to receive(:_setup_notifier)

      subject
    end

    context "without the group or plugin option" do
      it "initializes the empty scope" do
        expect(subject.scope).to eq(groups: [], plugins: [])
      end
    end

    context "with the group option" do
      let(:options) do
        {
          group:              %w(backend frontend),
          guardfile_contents: "group :backend do; end; "\
          "group :frontend do; end; group :excluded do; end"
        }
      end

      it "initializes the group scope" do
        expect(subject.scope[:plugins]).to be_empty
        expect(subject.scope[:groups].count).to be 2
        expect(subject.scope[:groups][0].name).to eq :backend
        expect(subject.scope[:groups][1].name).to eq :frontend
      end
    end

    context "with the plugin option" do
      let(:options) do
        {
          plugin:             %w(cucumber jasmine),
          guardfile_contents: "guard :jasmine do; end; "\
            "guard :cucumber do; end; guard :coffeescript do; end"
        }
      end

      before do
        stub_const "Guard::Jasmine", Class.new(Guard::Plugin)
        stub_const "Guard::Cucumber", Class.new(Guard::Plugin)
        stub_const "Guard::CoffeeScript", Class.new(Guard::Plugin)
      end

      it "initializes the plugin scope" do
        expect(subject.scope[:groups]).to be_empty
        expect(subject.scope[:plugins].count).to be 2
        expect(subject.scope[:plugins][0].class).to eq ::Guard::Cucumber
        expect(subject.scope[:plugins][1].class).to eq ::Guard::Jasmine
      end
    end

    context "when debug is set to true" do
      let(:options) { { debug: true } }
      it "does not set up debugging" do
        expect(Guard::Internals::Debugging).to receive(:start)
        subject
      end
    end

    context "when debug is set to false" do
      let(:options) { { debug: false } }
      it "sets up debugging" do
        expect(Guard::Internals::Debugging).to_not receive(:start)
        subject
      end
    end

    context "with latency option" do
      let(:options) { { latency: 1.5 } }

      it "passes option to listener" do
        expect(Listen).to receive(:to).
          with(anything,  latency: 1.5) { listener }
        subject
      end
    end

    context "with force_polling option" do
      let(:options) { { force_polling: true } }

      it "pass option to listener" do
        expect(Listen).to receive(:to).
          with(anything, force_polling: true) { listener }
        subject
      end
    end
  end

  describe ".reset_groups" do
    subject do
      allow(Listen).to receive(:to).with(Dir.pwd, {})
      allow(Guard::Notifier).to receive(:turn_on)

      stub_guardfile(" ")
      stub_user_guard_rb

      guard = Guard.setup(guardfile: guardfile)

      @group_backend = guard.add_group(:backend)
      @group_backflip = guard.add_group(:backflip)
      guard
    end

    it "initializes default groups" do
      subject.reset_groups

      expect(subject.groups.map(&:name)).to eq [:common, :default]
      expect(subject.groups.map(&:options)).to eq [{}, {}]
    end
  end

  describe ".setup_scope" do
    subject { Guard.setup(options) }

    let(:guardfile) do
      %w(group guard).map do |scope|
        %w(foo bar baz).map do |name|
          "#{ scope } :#{ name } do; end;"
        end
      end.flatten.join
    end

    let(:listener) { instance_double(Listen::Listener) }

    before do
      stub_const "Guard::Foo", Class.new(Guard::Plugin)
      stub_const "Guard::Bar", Class.new(Guard::Plugin)
      stub_const "Guard::Baz", Class.new(Guard::Plugin)
      allow(Listen).to receive(:to).with(Dir.pwd, {}) { listener }
      allow(Guard::Notifier).to receive(:turn_on)
      stub_user_guard_rb
    end

    [:group, :plugin].each do |scope|
      context "with the global #{scope} option specified" do
        let(:options) do
          { :guardfile_contents => guardfile, scope => %w(foo bar) }
        end

        it "configures the scope according to the global option" do
          subject.setup_scope(scope => :baz)

          expect(subject.scope[:"#{scope}s"].map(&:name).map(&:to_s)).to \
            contain_exactly("foo", "bar")
        end
      end

      context "without the global #{scope} option specified" do
        let(:options) { { guardfile_contents: guardfile } }

        it "configures the scope according to the given option" do
          subject.setup_scope(scope => :baz)

          expect(subject.scope[:"#{scope}s"].map(&:name).map(&:to_s)).to \
            contain_exactly("baz")
        end
      end
    end
  end

  describe "._relative_pathname" do
    subject { Guard.send(:_relative_pathname, raw_path) }

    let(:pwd) { Pathname("/project") }

    before { allow(Pathname).to receive(:pwd).and_return(pwd) }

    context "with file in project directory" do
      let(:raw_path) { "/project/foo" }
      it { is_expected.to eq(Pathname("foo")) }
    end

    context "with file within project" do
      let(:raw_path) { "/project/spec/models/foo_spec.rb" }
      it { is_expected.to eq(Pathname("spec/models/foo_spec.rb")) }
    end

    context "with file in parent directory" do
      let(:raw_path) { "/foo" }
      it { is_expected.to eq(Pathname("../foo")) }
    end

    context "with file on another drive (e.g. Windows)" do
      let(:raw_path) { "d:/project/foo" }
      let(:pathname) { instance_double(Pathname) }

      before do
        allow_any_instance_of(Pathname).to receive(:relative_path_from).
          with(pwd).and_raise(ArgumentError)
      end

      it { is_expected.to eq(Pathname.new("d:/project/foo")) }
    end
  end

  describe ".reset_plugins" do
    before do
      allow(Listen).to receive(:to).with(Dir.pwd, {})
      allow(Guard::Notifier).to receive(:turn_on)

      # TODO: clean this up (rework evaluator)
      stub_guardfile(" ")
      stub_user_guard_rb

      module Guard
        class FooBar < ::Guard::Plugin; end
      end
    end

    subject do
      ::Guard.setup(guardfile: guardfile).tap { |g| g.add_plugin(:foo_bar) }
    end

    after do
      ::Guard.instance_eval { remove_const(:FooBar) }
    end

    it "return clear the plugins array" do
      expect(subject.plugins.map(&:name)).to eq(%w(reevaluator foobar))

      subject.reset_plugins

      expect(subject.plugins).to be_empty
    end
  end

  describe ".reset_options" do
    before do
      allow(Listen).to receive(:to).with(File.join(Dir.pwd, "abc"), {})
      allow(Listen).to receive(:to).with(Dir.pwd, {})
      allow(Guard::Notifier).to receive(:turn_on)

      stub_guardfile(" ")
      stub_user_guard_rb
    end

    it "clears options to defaults" do
      Guard.setup(watchdir: "abc")
      Guard.reset_options({})
      expect(Guard.options).to include("watchdir" => nil)
    end

    it "merges defaults with provided options" do
      Guard.setup(group: "foo")
      Guard.reset_options(group: "bar")
      expect(Guard.options).to include("group" => "bar")
    end

    it "includes default options" do
      Guard.setup
      Guard.reset_options({})
      expect(Guard.options).to include("plugin" => [])
    end

    it "works without Guard.setup" do
      Guard.reset_options(group: "bar")
      expect(Guard.options).to include("group" => "bar")
      expect(Guard.options).to include("plugin" => [])
    end
  end

  describe ".evaluate_guardfile" do
    # Any plugin, so that we don't get error about no plugins
    # (other than built-in ones)
    let(:foo_plugin) { instance_double(Guard::Plugin, name: "Foo") }

    it "evaluates the Guardfile" do
      allow(Guard).to receive(:evaluator).and_return(evaluator)
      allow(Guard).to receive(:plugins).and_return([foo_plugin])
      expect(evaluator).to receive(:evaluate_guardfile)

      Guard.evaluate_guardfile
    end
  end

  describe "._setup_signal_traps", speed: "slow" do
    before do
      allow(::Guard).to receive(:evaluate_guardfile)
      allow(Listen).to receive(:to).with(Dir.pwd, {})
      allow(Guard::Notifier).to receive(:turn_on)
      ::Guard.setup
    end

    unless windows? || defined?(JRUBY_VERSION)
      context "when receiving SIGUSR1" do
        it "pauses Guard" do
          expect(::Guard).to receive(:async_queue_add).
            with([:guard_pause, :paused])

          Process.kill :USR1, Process.pid
          sleep 1
        end
      end

      context "when receiving SIGUSR2" do
        it "un-pause Guard" do
          expect(Guard).to receive(:async_queue_add).
            with([:guard_pause, :unpaused])

          Process.kill :USR2, Process.pid
          sleep 1
        end
      end

      context "when receiving SIGINT" do
        context "with an interactor" do
          it "delegates to the Pry thread" do
            expect(Guard.interactor).to receive(:handle_interrupt)
            Process.kill :INT, Process.pid
            sleep 1
          end
        end
      end
    end
  end

  # TODO: remove this method since it's private
  describe "._setup_notifier" do
    before do
      stub_guardfile(" ")
      stub_user_guard_rb
    end

    context "with the notify option enabled" do
      context "without the environment variable GUARD_NOTIFY set" do
        before { ENV["GUARD_NOTIFY"] = nil }

        it "turns on the notifier on" do
          expect(::Guard::Notifier).to receive(:turn_on)

          allow(Listen).to receive(:to).with(Dir.pwd, {})
          ::Guard.setup(notify: true)
        end
      end

      context "with the environment variable GUARD_NOTIFY set to true" do
        before { ENV["GUARD_NOTIFY"] = "true" }

        it "turns on the notifier on" do
          expect(::Guard::Notifier).to receive(:turn_on)

          allow(Listen).to receive(:to).with(Dir.pwd, {})
          ::Guard.setup(notify: true)
        end
      end

      context "with the environment variable GUARD_NOTIFY set to false" do
        before { ENV["GUARD_NOTIFY"] = "false" }

        it "turns on the notifier off" do
          expect(::Guard::Notifier).to receive(:turn_off)

          allow(Listen).to receive(:to).with(Dir.pwd, {})
          ::Guard.setup(notify: true)
        end
      end
    end

    context "with the notify option disable" do
      context "without the environment variable GUARD_NOTIFY set" do
        before { ENV["GUARD_NOTIFY"] = nil }

        it "turns on the notifier off" do
          expect(::Guard::Notifier).to receive(:turn_off)

          allow(Listen).to receive(:to).with(Dir.pwd, {})
          ::Guard.setup(notify: false)
        end
      end

      context "with the environment variable GUARD_NOTIFY set to true" do
        before { ENV["GUARD_NOTIFY"] = "true" }

        it "turns on the notifier on" do
          expect(::Guard::Notifier).to receive(:turn_off)

          allow(Listen).to receive(:to).with(Dir.pwd, {})
          ::Guard.setup(notify: false)
        end
      end

      context "with the environment variable GUARD_NOTIFY set to false" do
        before { ENV["GUARD_NOTIFY"] = "false" }

        it "turns on the notifier off" do
          expect(::Guard::Notifier).to receive(:turn_off)

          allow(Listen).to receive(:to).with(Dir.pwd, {})
          ::Guard.setup(notify: false)
        end
      end
    end
  end

  describe "._setup_notifier" do
    context "with the notify option enabled" do
      let(:options) { Guard::Options.new(notify: true) }
      before { allow(::Guard).to receive(:options) { options } }

      context "without the environment variable GUARD_NOTIFY set" do
        before { ENV["GUARD_NOTIFY"] = nil }

        it_should_behave_like "notifier enabled"
      end

      context "with the environment variable GUARD_NOTIFY set to true" do
        before { ENV["GUARD_NOTIFY"] = "true" }

        it_should_behave_like "notifier enabled"
      end

      context "with the environment variable GUARD_NOTIFY set to false" do
        before { ENV["GUARD_NOTIFY"] = "false" }

        it_should_behave_like "notifier disabled"
      end
    end

    context "with the notify option disabled" do
      let(:options) { Guard::Options.new(notify: false) }
      before { allow(::Guard).to receive(:options) { options } }

      context "without the environment variable GUARD_NOTIFY set" do
        before { ENV["GUARD_NOTIFY"] = nil }

        it_should_behave_like "notifier disabled"
      end

      context "with the environment variable GUARD_NOTIFY set to true" do
        before { ENV["GUARD_NOTIFY"] = "true" }

        it_should_behave_like "notifier disabled"
      end

      context "with the environment variable GUARD_NOTIFY set to false" do
        before { ENV["GUARD_NOTIFY"] = "false" }

        it_should_behave_like "notifier disabled"
      end
    end
  end

  # TODO: these should be interactor tests
  describe ".interactor" do
    subject { Guard.interactor }

    before do
      allow(Listen).to receive(:to).with(Dir.pwd, {})
      allow(evaluator).to receive(:evaluate_guardfile)
      allow(Guard::Notifier).to receive(:turn_on)

      stub_guardfile(" ")
      stub_user_guard_rb

      @interactor_enabled = Guard::Interactor.enabled?
    end

    after { Guard::Interactor.enabled = @interactor_enabled }

    context "with CLI options" do
      before { Guard::Interactor.enabled = true }

      context "with interactions enabled" do
        before { Guard.setup(no_interactions: false) }
        it { is_expected.to be_interactive }
      end

      context "with interactions disabled" do
        before { Guard.setup(no_interactions: true) }
        it { is_expected.to_not be_interactive }
      end
    end

    # TODO: these are interactor tests disguised as integration tests
    context "with DSL options" do

      context "with interactions enabled" do
        before do
          Guard::Interactor.enabled = true
          Guard.setup
        end

        it { is_expected.to be_interactive }
      end

      context "with interactions disabled" do
        before do
          Guard::Interactor.enabled = false
          Guard.setup
        end

        it { is_expected.to_not be_interactive }
      end
    end
  end
end
