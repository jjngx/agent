// Copyright (c) F5, Inc.
//
// This source code is licensed under the Apache License, Version 2.0 license found in the
// LICENSE file in the root directory of this source tree.

package main

import (
	"log"

	"go.opentelemetry.io/collector/confmap/provider/envprovider"
	"go.opentelemetry.io/collector/confmap/provider/fileprovider"
	"go.opentelemetry.io/collector/confmap/provider/httpprovider"
	"go.opentelemetry.io/collector/confmap/provider/httpsprovider"
	"go.opentelemetry.io/collector/confmap/provider/yamlprovider"

	"github.com/nginx/agent/v3/test/mock/collector/mock-collector/auth"
	"github.com/open-telemetry/opentelemetry-collector-contrib/exporter/prometheusexporter"
	"github.com/open-telemetry/opentelemetry-collector-contrib/processor/resourceprocessor"
	"go.opentelemetry.io/collector/connector"
	"go.opentelemetry.io/collector/exporter"
	"go.opentelemetry.io/collector/exporter/debugexporter"
	"go.opentelemetry.io/collector/exporter/otlpexporter"
	"go.opentelemetry.io/collector/exporter/otlphttpexporter"
	"go.opentelemetry.io/collector/extension"
	"go.opentelemetry.io/collector/processor"
	"go.opentelemetry.io/collector/processor/batchprocessor"
	"go.opentelemetry.io/collector/receiver"
	"go.opentelemetry.io/collector/receiver/otlpreceiver"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/confmap"
	"go.opentelemetry.io/collector/otelcol"
)

func main() {
	println("Starting mock collector")

	info := component.BuildInfo{
		Command:     "mock-collector",
		Description: "Mock OTel Collector distribution for Developers",
		Version:     "1.0.0",
	}

	set := otelcol.CollectorSettings{
		BuildInfo: info,
		Factories: components,
		ConfigProviderSettings: otelcol.ConfigProviderSettings{
			ResolverSettings: confmap.ResolverSettings{
				ProviderFactories: []confmap.ProviderFactory{
					envprovider.NewFactory(),
					fileprovider.NewFactory(),
					httpprovider.NewFactory(),
					httpsprovider.NewFactory(),
					yamlprovider.NewFactory(),
				},
				URIs: []string{"/etc/otel-collector.yaml"},
			},
		},
	}

	cmd := otelcol.NewCommand(set)
	if err := cmd.Execute(); err != nil {
		log.Fatalf("collector server run finished with error: %v", err)
	}
}

func components() (otelcol.Factories, error) {
	factories := otelcol.Factories{}

	authFactory := auth.NewFactory()
	factories.Extensions = make(map[component.Type]extension.Factory)
	factories.Extensions[authFactory.Type()] = authFactory

	otlpReceiverFactory := otlpreceiver.NewFactory()
	factories.Receivers = make(map[component.Type]receiver.Factory)
	factories.Receivers[otlpReceiverFactory.Type()] = otlpReceiverFactory

	exportersList := []exporter.Factory{
		debugexporter.NewFactory(),
		otlpexporter.NewFactory(),
		prometheusexporter.NewFactory(),
		otlphttpexporter.NewFactory(),
	}
	factories.Exporters = make(map[component.Type]exporter.Factory)
	for _, exporterFactory := range exportersList {
		factories.Exporters[exporterFactory.Type()] = exporterFactory
	}
	processorsList := []processor.Factory{
		batchprocessor.NewFactory(),
		resourceprocessor.NewFactory(),
	}
	factories.Processors = make(map[component.Type]processor.Factory)
	for _, processorFactory := range processorsList {
		factories.Processors[processorFactory.Type()] = processorFactory
	}

	factories.ProcessorModules = make(map[component.Type]string, len(factories.Processors))

	factories.Connectors = make(map[component.Type]connector.Factory)

	return factories, nil
}
