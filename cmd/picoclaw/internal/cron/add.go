package cron

import (
	"fmt"
	"time"

	"github.com/spf13/cobra"

	"github.com/sipeed/picoclaw/pkg/cron"
)

func newAddCommand(storePath func() string) *cobra.Command {
	var (
		name    string
		message string
		every   int64
		cronExp string
		at      int64
		command string
		deliver bool
		channel string
		to      string
	)

	cmd := &cobra.Command{
		Use:   "add",
		Short: "Add a new scheduled job",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if every <= 0 && cronExp == "" && at <= 0 {
				return fmt.Errorf("one of --every, --cron, or --at must be specified")
			}

			var schedule cron.CronSchedule
			if at > 0 {
				atMS := time.Now().UnixMilli() + (at * 1000)
				schedule = cron.CronSchedule{Kind: "at", AtMS: &atMS}
			} else if every > 0 {
				everyMS := every * 1000
				schedule = cron.CronSchedule{Kind: "every", EveryMS: &everyMS}
			} else {
				schedule = cron.CronSchedule{Kind: "cron", Expr: cronExp}
			}

			cs := cron.NewCronService(storePath(), nil)
			job, err := cs.AddJob(name, schedule, message, deliver, channel, to)
			if err != nil {
				return fmt.Errorf("error adding job: %w", err)
			}

			if command != "" {
				job.Payload.Command = command
				if err := cs.UpdateJob(job); err != nil {
					return fmt.Errorf("error updating job with command payload: %w", err)
				}
			}

			fmt.Printf("✓ Added job '%s' (%s)\n", job.Name, job.ID)

			return nil
		},
	}

	cmd.Flags().StringVarP(&name, "name", "n", "", "Job name")
	cmd.Flags().StringVarP(&message, "message", "m", "", "Message for agent")
	cmd.Flags().Int64VarP(&every, "every", "e", 0, "Run every N seconds")
	cmd.Flags().StringVarP(&cronExp, "cron", "c", "", "Cron expression (e.g. '0 9 * * *')")
	cmd.Flags().Int64VarP(&at, "at", "a", 0, "Run once in N seconds")
	cmd.Flags().StringVarP(&command, "command", "x", "", "Shell command to execute directly")
	cmd.Flags().BoolVarP(&deliver, "deliver", "d", false, "Deliver response to channel")
	cmd.Flags().StringVar(&to, "to", "", "Recipient for delivery")
	cmd.Flags().StringVar(&channel, "channel", "", "Channel for delivery")

	_ = cmd.MarkFlagRequired("name")
	_ = cmd.MarkFlagRequired("message")
	cmd.MarkFlagsMutuallyExclusive("every", "cron", "at")

	return cmd
}
